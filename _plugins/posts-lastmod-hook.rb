require 'open3'
require 'time'

# Include the first commit too: a translation can be newer than its source date.
Jekyll::Hooks.register :posts, :pre_render do |post|
  source = post.site.source
  path = post.path.delete_prefix("#{source}/")
  committed_at, status = Open3.capture2('git', '-C', source, 'log', '-1', '--format=%aI', '--', path)
  dates = [post.date, post.data['last_modified_at']]
  dates << committed_at.strip if status.success? && !committed_at.strip.empty?
  parsed_dates = dates.compact.filter_map do |date|
    Time.parse(date.to_s)
  rescue ArgumentError
    nil
  end
  post.data['last_modified_at'] = parsed_dates.max.iso8601 unless parsed_dates.empty?
end
