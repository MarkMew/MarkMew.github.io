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
end
