#!/usr/bin/env ruby
#
# Generate multi-language sitemap
# Usage: ruby tools/generate_sitemap.rb [output_dir]

require 'fileutils'
require 'yaml'
require 'date'
require 'time'

# Allow YAML to deserialize Date objects
YAML::ENGINE.yamler = 'psych' if YAML.respond_to?(:engine=)

output_dir = ARGV[0] || '_site'
site_url = 'https://www.markmew.com'
posts_base = '_posts'

all_posts = []

# Scan each language directory in _posts
if Dir.exist?(posts_base)
  Dir.glob(File.join(posts_base, '*')).each do |lang_dir|
    next unless File.directory?(lang_dir)
    lang_folder = File.basename(lang_dir)
    
    # Map folder name to lang code
    lang_code = case lang_folder
                when 'zh' then 'zh-TW'
                when 'en' then 'en'
                when 'jp' then 'ja'
                else lang_folder
                end
    
    # Find all markdown files in this language directory
    Dir.glob(File.join(lang_dir, '*.md')).sort.reverse.each do |post_path|
      begin
        content = File.read(post_path)
        
        # Extract YAML frontmatter
        if content =~ /\A---\s*\n(.*?)\n---\s*\n/m
          frontmatter_str = $1
          post_data = YAML.safe_load(
            frontmatter_str,
            permitted_classes: [Date, Time],
            aliases: true
          ) || {}
        else
          next
        end
        
        # Extract title and date from filename: YYYY-MM-DD-title.md
        filename = File.basename(post_path)
        if filename =~ /^(\d{4})-(\d{1,2})-(\d{1,2})-(.+)\.md$/
          post_title = $4
        else
          next
        end
        
        # Build post URL
        post_url = "/posts/#{post_title}/"
        
        # Prepend language path for non-default languages
        if lang_code != 'zh-TW'
          case lang_code
          when 'en'
            post_url = "/en#{post_url}"
          when 'ja'
            post_url = "/ja#{post_url}"
          else
            post_url = "/#{lang_code}#{post_url}"
          end
        end
        
        # Get last modified date
        lastmod = post_data['last_modified_at'] || post_data['date']
        if lastmod.nil?
          lastmod = File.mtime(post_path).to_datetime.to_s
        elsif lastmod.is_a?(Date) || lastmod.is_a?(Time)
          lastmod = lastmod.to_datetime.to_s
        else
          lastmod = lastmod.to_s
        end
        
        all_posts << {
          url: post_url,
          lastmod: lastmod,
          lang: lang_code
        }
      rescue Psych::Exception => e
        warn "Sitemap: Error parsing #{post_path}: #{e.message}"
      rescue => e
        warn "Sitemap: Error processing #{post_path}: #{e.message}"
      end
    end
  end
end

# Build sitemap XML
sitemap_urls = []

# Add homepage
sitemap_urls << {
  loc: "#{site_url}/",
  lastmod: Time.now.to_datetime.to_s,
  changefreq: 'daily',
  priority: '1.0'
}

# Add language homes
['en', 'ja'].each do |lang|
  sitemap_urls << {
    loc: "#{site_url}/#{lang}/",
    lastmod: Time.now.to_datetime.to_s,
    changefreq: 'daily',
    priority: '0.8'
  }
end

# Add all posts
all_posts.each do |post|
  sitemap_urls << {
    loc: "#{site_url}#{post[:url]}",
    lastmod: post[:lastmod],
    changefreq: 'monthly',
    priority: '0.9'
  }
end

# Add hub pages
hub_pages = [
  '/en/archives/', '/en/categories/', '/en/tags/',
  '/ja/archives/', '/ja/categories/', '/ja/tags/'
]
hub_pages.each do |hub|
  sitemap_urls << {
    loc: "#{site_url}#{hub}",
    lastmod: Time.now.to_datetime.to_s,
    changefreq: 'weekly',
    priority: '0.6'
  }
end

# Generate XML
sitemap_xml = %(<?xml version="1.0" encoding="UTF-8"?>\n)
sitemap_xml += %(<?xml-stylesheet type="text/xsl" href="/sitemap.xsl"?>\n)
sitemap_xml += %(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n)

sitemap_urls.each do |entry|
  sitemap_xml += %(  <url>\n)
  sitemap_xml += %(    <loc>#{entry[:loc]}</loc>\n)
  sitemap_xml += %(    <lastmod>#{entry[:lastmod]}</lastmod>\n) if entry[:lastmod]
  sitemap_xml += %(    <changefreq>#{entry[:changefreq]}</changefreq>\n) if entry[:changefreq]
  sitemap_xml += %(    <priority>#{entry[:priority]}</priority>\n) if entry[:priority]
  sitemap_xml += %(  </url>\n)
end

sitemap_xml += %(</urlset>\n)

# Write to output
FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)
sitemap_path = File.join(output_dir, 'sitemap.xml')
File.write(sitemap_path, sitemap_xml)

langs = all_posts.map{|p|p[:lang]}.uniq.sort.join(', ')
puts "✓ Sitemap generated: #{all_posts.length} posts across #{langs}"
puts "  Output: #{sitemap_path}"
