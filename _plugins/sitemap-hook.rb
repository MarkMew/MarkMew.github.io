require_relative '../tools/generate_sitemap'

# Polyglot fires this after every language has been written and restores site.dest.
Jekyll::Hooks.register :polyglot, :post_write do |site|
  count = MarkMew::Sitemap.generate(site.dest, site.config)
  Jekyll.logger.info('Sitemap:', "Generated #{count} canonical pages")
end
