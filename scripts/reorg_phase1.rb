#!/usr/bin/env ruby
# One-shot Phase 1 reorg: the four existing source files were git-mv'd into
# folders and two new Core files were created. This removes the now-stale
# top-level file references and re-registers all six at their new paths, in
# groups that mirror the on-disk layout.

require "xcodeproj"
require "pathname"

PROJECT_PATH = File.expand_path("../OpenDiskTest.xcodeproj", __dir__)
SRC_ROOT     = File.expand_path("../OpenDiskTest", __dir__)
TARGET_NAME  = "OpenDiskTest"

# Old basenames whose stale references must be purged (renames + moves).
STALE_BASENAMES = %w[
  ContentView.swift
  OpenDiskTestApp.swift
  UpdateChecker.swift
  DiskSpeedTestViewModel.swift
].freeze

# New on-disk paths (relative to OpenDiskTest/) to register.
NEW_PATHS = %w[
  Core/Color+Hex.swift
  Core/Theme.swift
  Core/UpdateChecker.swift
  App/OpenDiskTestApp.swift
  Tools/DiskSpeed/DiskSpeedDetailView.swift
  Tools/DiskSpeed/DiskSpeedTestViewModel.swift
].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)
target  = project.targets.find { |t| t.name == TARGET_NAME }
root    = project.main_group[TARGET_NAME]

# 1. Purge stale references by basename.
removed = []
project.files.dup.each do |f|
  next unless STALE_BASENAMES.include?(File.basename(f.path.to_s))
  f.remove_from_project
  removed << f.path.to_s
end

# 2. Register the six files at their new locations.
added = []
NEW_PATHS.each do |rel|
  abs = File.join(SRC_ROOT, rel)
  abort "Missing on disk: #{rel}" unless File.exist?(abs)

  parts = rel.split("/")
  parts.pop # filename
  group = root
  parts.each do |segment|
    child = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == segment }
    child ||= group.new_group(segment, segment)
    group = child
  end
  ref = group.new_reference(abs)
  target.add_file_references([ref])
  added << rel
end

project.save
puts "Removed stale refs: #{removed.sort.uniq.join(', ')}"
puts "Registered: #{added.join(', ')}"
puts "Target now has #{target.source_build_phase.files.count} source files."
