#!/usr/bin/env ruby

require "fileutils"

site_dir = ARGV[0] || "_site"
xsl_source = File.join("tools", "sitemap.xsl")
xsl_target = File.join(site_dir, "sitemap.xsl")
stylesheet_tag = %(<?xml-stylesheet type="text/xsl" href="/sitemap.xsl"?>)

unless Dir.exist?(site_dir)
  abort("Site output directory not found: #{site_dir}")
end

unless File.exist?(xsl_source)
  abort("Sitemap XSL source not found: #{xsl_source}")
end

FileUtils.cp(xsl_source, xsl_target)

Dir.glob(File.join(site_dir, "**", "sitemap.xml")).each do |sitemap_path|
  content = File.read(sitemap_path)
  next if content.include?("xml-stylesheet")

  if content.start_with?("<?xml")
    content = content.sub(/\A<\?xml[^>]*\?>\s*/m) { |match| "#{match}#{stylesheet_tag}\n" }
  else
    content = %(<?xml version="1.0" encoding="UTF-8"?>\n#{stylesheet_tag}\n) + content
  end

  File.write(sitemap_path, content)
end
