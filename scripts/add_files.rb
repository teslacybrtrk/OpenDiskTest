#!/usr/bin/env ruby
# Registers Swift source files into the OpenDiskTest target.
#
# The project is objectVersion 56 (explicit file refs, no folder-sync), so any
# new .swift file must be added to both a PBXGroup and the target's Sources
# build phase or it simply won't compile. This wraps the `xcodeproj` gem to do
# that idempotently.
#
# Usage:
#   ruby scripts/add_files.rb OpenDiskTest/Core/Theme.swift OpenDiskTest/App/SuiteModel.swift ...
#
# Paths are relative to the repo root. Xcode groups are created to mirror the
# on-disk folder structure under the top-level "OpenDiskTest" group. Re-running
# with already-registered files is a no-op.

require "xcodeproj"
require "pathname"

PROJECT_PATH = File.expand_path("../OpenDiskTest.xcodeproj", __dir__)
TARGET_NAME  = "OpenDiskTest"
ROOT_GROUP   = "OpenDiskTest" # top-level group whose path is the source folder

project = Xcodeproj::Project.open(PROJECT_PATH)
target  = project.targets.find { |t| t.name == TARGET_NAME }
abort "Target #{TARGET_NAME} not found" unless target

root = project.main_group[ROOT_GROUP]
abort "Group #{ROOT_GROUP} not found" unless root

# All file references already known to the project, by absolute path.
existing = {}
project.files.each { |f| existing[f.real_path.to_s] = f rescue nil }

added = []
skipped = []

ARGV.each do |arg|
  abs = File.expand_path(arg)
  unless File.exist?(abs)
    abort "File does not exist on disk: #{arg}"
  end

  if existing[abs]
    skipped << arg
    next
  end

  # Build/locate nested groups mirroring the path under OpenDiskTest/.
  rel = Pathname.new(abs).relative_path_from(Pathname.new(root.real_path)).to_s
  parts = rel.split("/")
  filename = parts.pop

  group = root
  parts.each do |segment|
    child = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == segment }
    child ||= group.new_group(segment, segment)
    group = child
  end

  file_ref = group.new_reference(abs)
  target.add_file_references([file_ref]) if filename.end_with?(".swift")
  existing[abs] = file_ref
  added << arg
end

project.save

puts "Added #{added.count} file(s):"
added.each { |f| puts "  + #{f}" }
unless skipped.empty?
  puts "Already registered (#{skipped.count}):"
  skipped.each { |f| puts "  = #{f}" }
end
