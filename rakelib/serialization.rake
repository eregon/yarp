# frozen_string_literal: true

task "test:java_loader" do
  fixtures = File.expand_path("../test/yarp/fixtures", __dir__)

  $:.unshift(File.expand_path("../lib", __dir__))
  require "yarp"
  raise "this task requires the FFI backend" unless YARP::BACKEND == :FFI
  require "fileutils"
  require 'java'
  require_relative '../tmp/yarp.jar'
  java_import 'org.yarp.Nodes$Source'

  Dir["**/*.txt", base: fixtures].each do |relative|
    path = "#{fixtures}/#{relative}"
    puts
    puts path
    serialized = YARP.const_get(:Debug).dump_file_no_location_fields(path)
    source_bytes = File.binread(path).unpack('c*')
    source = Source.new(source_bytes.to_java(:byte))
    parse_result = org.yarp.Loader.load(serialized.unpack('c*'), source)
    puts parse_result.value
  end
end
