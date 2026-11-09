#!/usr/bin/env ruby

require 'rexml/document'
require 'rexml/xpath'
require 'uri'
require 'cgi'
require 'json'
require 'time'
require 'yaml'

site_dir = ARGV[0] || '_site'
sitemap_path = File.join(site_dir, 'sitemap.xml')
baseline_path = ARGV[1]
namespace = 'http://www.sitemaps.org/schemas/sitemap/0.9'

abort "Sitemap not found: #{sitemap_path}" unless File.file?(sitemap_path)

def read_sitemap(path, namespace, require_no_stylesheet:)
  xml = File.read(path, encoding: 'UTF-8')
  abort "XSLT instruction remains in #{path}" if require_no_stylesheet && xml.match?(/<\?xml-stylesheet\b/i)

  document = REXML::Document.new(xml)
  abort "Invalid sitemap namespace in #{path}" unless document.root&.name == 'urlset' && document.root.namespace == namespace

  urls = REXML::XPath.match(document, '/s:urlset/s:url', { 's' => namespace })
  locations = urls.map { |entry| REXML::XPath.first(entry, 's:loc', { 's' => namespace })&.text }
  abort "Sitemap contains an empty URL: #{path}" if locations.any? { |url| url.nil? || url.empty? }
  abort "Sitemap contains duplicate URLs: #{path}" unless locations.uniq.size == locations.size
  locations.each do |url|
    parsed = URI.parse(url)
    abort "Invalid sitemap URL: #{url}" unless parsed.is_a?(URI::HTTPS) && parsed.host == 'www.markmew.com'
  end

  [urls, locations]
rescue REXML::ParseException, URI::InvalidURIError => error
  abort "Invalid sitemap XML or URL in #{path}: #{error.message}"
end

def snapshot(element)
  [element.expanded_name, element.attributes.to_a.map { |attribute| [attribute.expanded_name, attribute.value] }.sort,
   element.children.grep(REXML::Element).map { |child| snapshot(child) }, element.texts.map(&:value).join.strip]
end

urls, locations = read_sitemap(sitemap_path, namespace, require_no_stylesheet: true)
baseurl = YAML.load_file('_config.yml').fetch('baseurl', '').to_s.sub(%r{/$}, '')
urls.each do |entry|
  url = REXML::XPath.first(entry, 's:loc', { 's' => namespace }).text
  path = URI::DEFAULT_PARSER.unescape(URI.parse(url).path).delete_prefix(baseurl)
  file = File.join(site_dir, path.delete_prefix('/'), 'index.html')
  abort "Sitemap target was not built: #{url}" unless File.file?(file)
  html = File.read(file, encoding: 'UTF-8')
  attribute = ->(tag, name) { CGI.unescapeHTML(tag[/\b#{name}="([^"]*)"/, 1].to_s) }
  blocked = html.scan(/<meta\b[^>]*>/).any? do |tag|
    attribute.call(tag, 'name').downcase == 'robots' &&
      attribute.call(tag, 'content').downcase.split(/[\s,]+/).include?('noindex')
  end
  abort "Sitemap includes a noindex page: #{url}" if blocked
  canonical = html.scan(/<link\b[^>]*>/).find { |tag| attribute.call(tag, 'rel') == 'canonical' }
  abort "Sitemap URL differs from canonical: #{url}" unless attribute.call(canonical.to_s, 'href') == url
  lastmod = REXML::XPath.first(entry, 's:lastmod', { 's' => namespace })&.text
  next unless lastmod

  data = JSON.parse(html[/<script type="application\/ld\+json">(.*?)<\/script>/m, 1] || '{}')
  modified = data['dateModified'] || data['datePublished']
  abort "Sitemap lastmod differs from page metadata: #{url}" unless modified && Time.iso8601(lastmod) == Time.iso8601(modified)
end
{ 'en' => 'en/posts', 'ja' => 'ja/posts' }.each do |language, directory|
  next unless Dir.exist?(File.join(site_dir, directory))

  abort "Missing #{language} post URLs in sitemap" unless locations.any? { |url| URI.parse(url).path.start_with?("/#{language}/posts/") }
end

if baseline_path
  abort "Baseline not found: #{baseline_path}" unless File.file?(baseline_path)
  baseline_urls, = read_sitemap(baseline_path, namespace, require_no_stylesheet: false)
  abort 'Sitemap URL entries or metadata differ from baseline' unless urls.map { |entry| snapshot(entry) } == baseline_urls.map { |entry| snapshot(entry) }
end

puts "Sitemap valid: #{urls.size} URLs, correct namespace, no XSLT instruction"
