#!/usr/bin/env ruby
# Read Fastlane YAML as data without instantiating its Ruby object tags.
require 'yaml'
require 'time'

begin
  session = ENV.fetch('FASTLANE_SESSION').gsub('\\n', "\n")
  root = YAML.parse(session).root
  raise 'Expected a cookie list.' unless root.is_a?(Psych::Nodes::Sequence)

  cookie = root.children.map do |node|
    next unless node.is_a?(Psych::Nodes::Mapping)
    fields = {}
    node.children.each_slice(2) do |key, value|
      next unless key.is_a?(Psych::Nodes::Scalar) && %w[name domain expires value].include?(key.value)
      raise 'Invalid cookie field.' unless value.is_a?(Psych::Nodes::Scalar)
      fields[key.value] = value.value
    end
    fields if fields['name'] == 'ADCDownloadAuth' && ['apple.com', '.apple.com'].include?(fields['domain'])
  end.compact.find do |fields|
    fields['expires'] && Time.parse(fields['expires']) > Time.now
  end
  raise 'The Apple download cookie is missing or expired.' unless cookie
  value = cookie.fetch('value')
  raise 'Invalid download cookie.' unless value.match?(/\A[^\s;\x00-\x1f\x7f]+\z/)

  puts '# Netscape HTTP Cookie File'
  puts ['.apple.com', 'TRUE', '/', 'TRUE', Time.parse(cookie['expires']).to_i, 'ADCDownloadAuth', value].join("\t")
rescue StandardError
  # Parser errors can contain cookie values. Never print them in CI logs.
  warn '::error::Refresh XCODE_DOWNLOAD_SESSION with a valid Apple Developer download session.'
  exit 1
end
