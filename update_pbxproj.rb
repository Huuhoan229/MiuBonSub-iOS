require 'xcodeproj'
require 'fileutils'

project_path = 'ios/App/App.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |t| t.name == 'App' }

# Remove old NativeApp.swift if exists
app_target.source_build_phase.files.each do |file|
  if file.file_ref && file.file_ref.path == 'NativeApp.swift'
    file.file_ref.remove_from_project
  end
end

app_group = project.main_group.groups.find { |g| g.name == 'App' || g.path == 'App' }

def add_files_to_group(project, target, group, dir_path)
  Dir.glob("#{dir_path}/*").each do |path|
    if File.directory?(path)
      folder_name = File.basename(path)
      sub_group = group.groups.find { |g| g.name == folder_name || g.path == folder_name } || group.new_group(folder_name, folder_name)
      add_files_to_group(project, target, sub_group, path)
    elsif path.end_with?('.swift')
      file_name = File.basename(path)
      unless group.files.any? { |f| f.path == file_name }
        file_ref = group.new_file(path)
        target.source_build_phase.add_file_reference(file_ref)
      end
    end
  end
end

['Core', 'Models', 'ViewModels', 'Views'].each do |dir|
  sub_group = app_group.groups.find { |g| g.name == dir || g.path == dir } || app_group.new_group(dir, dir)
  add_files_to_group(project, app_target, sub_group, "ios/App/App/#{dir}")
end

project.save
puts "Successfully updated project.pbxproj with new Swift files"
