#!/usr/bin/env ruby
# Validate the built HTML, including reciprocal language links.
require 'cgi'
require 'json'
require 'uri'
require 'yaml'

destination = ARGV.fetch(0, '_site')
config = YAML.load_file('_config.yml')
origin = config.fetch('url').sub(%r{/$}, '')
baseurl = config.fetch('baseurl', '').to_s.sub(%r{/$}, '')
pages = {}
errors = []
source_languages = Hash.new { |hash, key| hash[key] = [] }
{ 'zh' => 'zh-TW', 'en' => 'en', 'jp' => 'ja' }.each do |folder, language|
  Dir.glob("_posts/#{folder}/*.md").each do |source|
    slug = File.basename(source).sub(/\A\d{4}-\d{2}-\d{2}-/, '').sub(/\.md\z/, '')
    source_languages[slug] << language
  end
end

Dir.glob(File.join(destination, '**', 'index.html')).each do |file|
  path = file.delete_prefix(destination).tr('\\', '/').sub(%r{/index\.html$}, '/')
  path = '/' if path.empty?
  url = "#{origin}#{baseurl}#{URI::DEFAULT_PARSER.escape(path)}"
  html = File.read(file, encoding: 'UTF-8')
  links = html.scan(/<link\b[^>]*>/)
  metas = html.scan(/<meta\b[^>]*>/)
  attribute = ->(tag, name) { CGI.unescapeHTML(tag[/\b#{Regexp.escape(name)}="([^"]*)"/, 1].to_s) }
  canonicals = links.select { |tag| attribute.call(tag, 'rel') == 'canonical' }.map { |tag| attribute.call(tag, 'href') }
  alternates = links.select { |tag| attribute.call(tag, 'hreflang') != '' }.to_h do |tag|
    [attribute.call(tag, 'hreflang'), attribute.call(tag, 'href')]
  end
  hreflang_count = links.count { |tag| attribute.call(tag, 'hreflang') != '' }
  og_url = metas.find { |tag| attribute.call(tag, 'property') == 'og:url' }
  og_locale = metas.find { |tag| attribute.call(tag, 'property') == 'og:locale' }
  robots = metas.find { |tag| attribute.call(tag, 'name') == 'robots' }
  noindex = attribute.call(robots.to_s, 'content').split(',').include?('noindex')
  html_lang = html[/<html\b[^>]*\blang="([^"]+)"/, 1]
  expected_lang = path.start_with?('/en/') ? 'en' : path.start_with?('/ja/') ? 'ja' : 'zh-TW'
  expected_locale = { 'en' => 'en_US', 'ja' => 'ja_JP', 'zh-TW' => 'zh_TW' }.fetch(expected_lang)
  errors << '/ja/about/: untranslated page should be noindex' if path == '/ja/about/' && !noindex

  if noindex && path != '/ja/about/'
    errors << "#{path}: noindex fallback has hreflang links" unless alternates.empty?
    errors << "#{path}: noindex fallback canonical is missing" unless canonicals.one?
    fallback_path = path.sub(%r{^/(en|ja)/}, '/')
    expected_fallback = "#{origin}#{baseurl}#{URI::DEFAULT_PARSER.escape(fallback_path)}"
    errors << "#{path}: noindex fallback canonical is not the source post" unless canonicals == [expected_fallback]
  else
    errors << "#{path}: expected one self canonical, got #{canonicals.inspect}" unless canonicals == [url]
  end
  errors << "#{path}: og:url differs from canonical" unless attribute.call(og_url.to_s, 'content') == canonicals.first
  errors << "#{path}: incorrect og:locale" unless attribute.call(og_locale.to_s, 'content') == expected_locale
  json_ld = html[/<script type="application\/ld\+json">(.*?)<\/script>/m, 1]
  if json_ld
    begin
      data = JSON.parse(json_ld)
      errors << "#{path}: JSON-LD URL differs from canonical" unless data['url'] == canonicals.first
    rescue JSON::ParserError
      errors << "#{path}: invalid JSON-LD"
    end
  end
  errors << "#{path}: HTML language #{html_lang.inspect}, expected #{expected_lang}" unless html_lang == expected_lang
  errors << "#{path}: duplicate hreflang codes" unless hreflang_count == alternates.size
  expected_alternates = case path
                        when '/', '/en/', '/ja/' then %w[zh-TW en ja x-default]
                        when '/about/', '/en/about/' then %w[zh-TW en]
                        when '/archives/', '/en/archives/', '/ja/archives/',
                             '/categories/', '/en/categories/', '/ja/categories/',
                             '/tags/', '/en/tags/', '/ja/tags/' then %w[zh-TW en ja]
                        when %r{^/(?:en/|ja/)?posts/([^/]+)/$}
                          languages = source_languages[Regexp.last_match(1)]
                          languages.size > 1 && !noindex ? languages : []
                        else []
                        end
  errors << "#{path}: hreflang set #{alternates.keys.inspect}, expected #{expected_alternates.inspect}" unless alternates.keys.sort == expected_alternates.sort
  errors << "#{path}: invalid or double language prefix" if html.match?(%r{/en/en/|/ja/ja/})
  pages[url] = { path: path, alternates: alternates }
end

pages.each do |url, page|
  page[:alternates].each do |lang, target|
    errors << "#{page[:path]}: missing hreflang target #{target}" unless pages.key?(target)
    next if lang == 'x-default' || !pages.key?(target)

    target_lang = pages[target][:alternates]
    errors << "#{page[:path]}: nonreciprocal #{lang} -> #{target}" unless target_lang.values.include?(url)
  end
end

puts "Checked #{pages.size} HTML pages; #{errors.size} SEO errors"
errors.first(30).each { |error| warn error }
exit(errors.empty? ? 0 : 1)
