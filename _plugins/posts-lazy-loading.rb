# frozen_string_literal: true

# Plugin to add lazy loading to all images in posts
Jekyll::Hooks.register :posts, :post_render do |post|
  next if post.content.nil?

  # Add loading="lazy" to all img tags that don't already have it
  post.content.gsub!(/<img\s+([^>]*?)>/i) do |match|
    tag = match
    # Skip if already has loading attribute
    unless tag.include?('loading=')
      tag.sub!(/<img\s+/i, '<img loading="lazy" ')
    end
    tag
  end
end
