# Collect the language versions that actually exist for each post URL.
module Jekyll
  class PostTranslations < Generator
    safe true
    priority :low

    def generate(site)
      translations = {}
      folders = { 'zh' => 'zh-TW', 'en' => 'en', 'jp' => 'ja' }

      folders.each do |folder, lang|
        Dir.glob(File.join('_posts', folder, '*.md'), base: site.source).each do |path|
          slug = File.basename(path).sub(/\A\d{4}-\d{2}-\d{2}-/, '').sub(/\.md\z/, '')
          (translations["/posts/#{slug}/"] ||= []) << lang
        end
      end

      site.data['post_translations'] = translations
    end
  end
end
