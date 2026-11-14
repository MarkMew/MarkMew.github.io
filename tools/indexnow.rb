#!/usr/bin/env ruby
# Notify IndexNow (Bing, Yandex, Seznam, ...) about posts changed between two commits.
#
# Usage: ruby tools/indexnow.rb BEFORE_SHA AFTER_SHA [--dry-run]
#   When BEFORE_SHA is empty, all-zero or unknown (manual run, new branch),
#   every post URL is submitted.
require 'json'
require 'net/http'
require 'open3'
require 'uri'
require 'yaml'

ENDPOINT = URI('https://api.indexnow.org/indexnow')
LANG_PREFIX = { 'zh' => '', 'en' => '/en', 'jp' => '/ja' }.freeze
POST_PATTERN = %r{\A_posts/(zh|en|jp)/\d{4}-\d{2}-\d{2}-(.+)\.md\z}

before, after = ARGV[0].to_s, ARGV[1].to_s
dry_run = ARGV.include?('--dry-run')
after = 'HEAD' if after.empty?

config = YAML.load_file('_config.yml')
origin = config.fetch('url').sub(%r{/$}, '')
host = URI(origin).host

key_file = Dir.glob('*.txt').find { |f| File.basename(f, '.txt').match?(/\A[0-9a-f]{32}\z/) }
abort 'IndexNow: key file (<32 hex>.txt) not found at repo root' unless key_file
key = File.basename(key_file, '.txt')
abort "IndexNow: #{key_file} must contain exactly the key" unless File.read(key_file).strip == key

def post_url(origin, path)
  match = path.match(POST_PATTERN) or return nil
  "#{origin}#{LANG_PREFIX.fetch(match[1])}/posts/#{match[2]}/"
end

valid_before = !before.empty? && before !~ /\A0+\z/ &&
               system('git', 'cat-file', '-e', "#{before}^{commit}", err: File::NULL)

paths =
  if valid_before
    out, status = Open3.capture2('git', 'diff', '--name-only', '--no-renames', before, after, '--', '_posts')
    abort 'IndexNow: git diff failed' unless status.success?
    out.lines.map(&:strip)
  else
    Dir.glob('_posts/*/*.md')
  end

urls = paths.filter_map { |path| post_url(origin, path) }.uniq.sort
if urls.empty?
  puts 'IndexNow: no post changes, nothing to submit'
  exit 0
end

# Home pages list the latest posts, so refresh them whenever a post changes.
urls += ["#{origin}/", "#{origin}/en/", "#{origin}/ja/"]
urls = urls.first(10_000)

puts "IndexNow: submitting #{urls.size} URL(s)"
urls.each { |url| puts "  #{url}" }
exit 0 if dry_run

body = { host: host, key: key, keyLocation: "#{origin}/#{key}.txt", urlList: urls }.to_json
response = Net::HTTP.post(ENDPOINT, body, 'Content-Type' => 'application/json; charset=utf-8')
puts "IndexNow: HTTP #{response.code} #{response.message}"
# 200 = OK, 202 = accepted (key validation pending)
abort "IndexNow: submission failed: #{response.body}" unless %w[200 202].include?(response.code)
