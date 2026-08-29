#!/usr/bin/env ruby
#
# Publish a raw Markdown variant of each post next to its built HTML output,
# so a Cloudflare Worker (or any edge proxy) can serve it when a client sends
# Accept: text/markdown, without requiring the paid Markdown for Agents feature.

Jekyll::Hooks.register :site, :post_write do |site|
  site.posts.docs.each do |post|
    html_dest = post.destination(site.dest)
    dir = File.dirname(html_dest)
    next unless Dir.exist?(dir)

    md_dest = File.join(dir, "index.md")
    File.write(md_dest, File.read(post.path))
  end

  # Homepage has no standalone Markdown source (it's a generated post list),
  # so build a minimal index of recent posts as its Markdown variant.
  posts = site.posts.docs.sort_by(&:date).reverse
  lines = []
  lines << "---"
  lines << "title: #{site.config['title']}"
  lines << "description: #{site.config['description'].to_s.strip}"
  lines << "---"
  lines << ""
  lines << "# #{site.config['title']}"
  lines << ""
  lines << site.config['description'].to_s.strip
  lines << ""
  lines << "## Recent Posts"
  posts.each do |post|
    lines << "- [#{post.data['title']}](#{post.url}) - #{post.date.strftime('%Y-%m-%d')}"
  end

  File.write(File.join(site.dest, "index.md"), lines.join("\n"))
end

