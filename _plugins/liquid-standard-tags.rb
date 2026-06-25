# Ensure Liquid's built-in tags are registered before Jekyll renders layouts.
#
# In this local Ruby/Bundler setup the Liquid tag classes are loaded, but the
# standard tags can be missing from Liquid::Template.tags. Register them
# explicitly without overriding Jekyll's own tags such as `include`.
{
  "assign" => ["liquid/tags/assign", "Assign"],
  "break" => ["liquid/tags/break", "Break"],
  "capture" => ["liquid/tags/capture", "Capture"],
  "case" => ["liquid/tags/case", "Case"],
  "comment" => ["liquid/tags/comment", "Comment"],
  "continue" => ["liquid/tags/continue", "Continue"],
  "cycle" => ["liquid/tags/cycle", "Cycle"],
  "decrement" => ["liquid/tags/decrement", "Decrement"],
  "for" => ["liquid/tags/for", "For"],
  "if" => ["liquid/tags/if", "If"],
  "ifchanged" => ["liquid/tags/ifchanged", "Ifchanged"],
  "increment" => ["liquid/tags/increment", "Increment"],
  "raw" => ["liquid/tags/raw", "Raw"],
  "tablerow" => ["liquid/tags/table_row", "TableRow"],
  "unless" => ["liquid/tags/unless", "Unless"]
}.each do |tag_name, tag_class|
  require tag_class[0]
  Liquid::Template.register_tag(tag_name, Liquid.const_get(tag_class[1])) unless Liquid::Template.tags[tag_name]
end
