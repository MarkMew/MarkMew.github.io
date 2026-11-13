#!/usr/bin/env ruby
# Generate a sitemap from the canonical HTML that was actually built.
require 'cgi'
require 'json'
require 'time'
require 'uri'
require 'yaml'

module MarkMew
  module Sitemap
    def self.generate(output_dir, config)
      output_dir = output_dir.sub(%r{[\\/]+$}, '')
      origin = config.fetch('url').sub(%r{/$}, '')
      baseurl = config.fetch('baseurl', '').to_s.sub(%r{/$}, '')
      entries = []

      Dir.glob('**/index.html', base: output_dir).sort.each do |relative|
        file = File.join(output_dir, relative)
        path = "/#{relative}".sub(%r{/index\.html$}, '/')
        # List articles and language hubs; exclude pagination and taxonomy detail pages.
        next unless path.match?(%r{\A/(?:en/|ja/)?(?:posts/[^/]+/|archives/|categories/|tags/)?\z})

        html = File.read(file, encoding: 'UTF-8')
        attribute = ->(tag, name) { CGI.unescapeHTML(tag[/\b#{name}="([^"]*)"/, 1].to_s) }
        noindex = html.scan(/<meta\b[^>]*>/).any? do |tag|
          attribute.call(tag, 'name').downcase == 'robots' &&
            attribute.call(tag, 'content').downcase.split(/[\s,]+/).include?('noindex')
        end
        next if noindex

        canonical_tags = html.scan(/<link\b[^>]*>/).select { |tag| attribute.call(tag, 'rel') == 'canonical' }
        url = "#{origin}#{baseurl}#{URI::DEFAULT_PARSER.escape(path)}"
        unless canonical_tags.one? && attribute.call(canonical_tags.first, 'href') == url
          raise "Sitemap: expected a self canonical in #{file}"
        end

        alternates = html.scan(/<link\b[^>]*>/).filter_map do |tag|
          hreflang = attribute.call(tag, 'hreflang')
          next if attribute.call(tag, 'rel') != 'alternate' || hreflang.empty?

          { hreflang: hreflang, href: attribute.call(tag, 'href') }
        end
        entry = { loc: url, alternates: alternates }
        if path.include?('/posts/')
          json_ld = html[/<script type="application\/ld\+json">(.*?)<\/script>/m, 1]
          data = json_ld ? JSON.parse(json_ld) : {}
          modified = data['dateModified'] || data['datePublished']
          entry[:lastmod] = Time.iso8601(modified).iso8601 if modified
        end
        entries << entry
      end

      raise "Sitemap: no canonical pages found in #{output_dir}" if entries.empty?

      xml = %(<?xml version="1.0" encoding="UTF-8"?>\n)
      xml << %(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n)
      entries.each do |entry|
        xml << "  <url>\n"
        xml << "    <loc>#{CGI.escapeHTML(entry[:loc])}</loc>\n"
        entry[:alternates].each do |alternate|
          xml << %(    <xhtml:link rel="alternate" hreflang="#{CGI.escapeHTML(alternate[:hreflang])}" href="#{CGI.escapeHTML(alternate[:href])}" />\n)
        end
        xml << "    <lastmod>#{CGI.escapeHTML(entry[:lastmod])}</lastmod>\n" if entry[:lastmod]
        xml << "  </url>\n"
      end
      xml << "</urlset>\n"
      File.write(File.join(output_dir, 'sitemap.xml'), xml, encoding: 'UTF-8')
      entries.size
    end
  end
end

if $PROGRAM_NAME == __FILE__
  config = YAML.load_file('_config.yml')
  count = MarkMew::Sitemap.generate(ARGV.fetch(0, '_site'), config)
  puts "Sitemap generated: #{count} canonical pages"
end
