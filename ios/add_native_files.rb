require 'xcodeproj'

project_path = 'Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Get the Runner group
runner_group = project.main_group['Runner']

# Add Objective-C source files
iperf3_bridge_m = runner_group.new_file('Iperf3Bridge.m')
iperf3_plugin_m = runner_group.new_file('Iperf3Plugin.m')

# Add to compile sources
target.add_file_references([iperf3_bridge_m, iperf3_plugin_m])

# Add Native group
native_group = runner_group.new_group('Native')
native_bridge_c = native_group.new_file('Native/iperf3_bridge.c')
target.add_file_references([native_bridge_c])

# Add SystemConfiguration framework
target.frameworks_build_phase.add_file_reference(
  project.frameworks_group.new_reference('System/Library/Frameworks/SystemConfiguration.framework')
)

# Add header search paths
target.build_configurations.each do |config|
  config.build_settings['HEADER_SEARCH_PATHS'] ||= ['$(inherited)']
  config.build_settings['HEADER_SEARCH_PATHS'] << '"$(SRCROOT)/Runner/Native"'
  config.build_settings['HEADER_SEARCH_PATHS'] << '"$(SRCROOT)/Runner/Native/iperf3"'
  config.build_settings['HEADER_SEARCH_PATHS'] << '"$(SRCROOT)/iperf3_lib"'
  
  # Add library search paths
  config.build_settings['LIBRARY_SEARCH_PATHS'] ||= ['$(inherited)']
  config.build_settings['LIBRARY_SEARCH_PATHS'] << '"$(SRCROOT)/iperf3_lib"'
  
  # Add other linker flags
  config.build_settings['OTHER_LDFLAGS'] ||= ['$(inherited)']
  config.build_settings['OTHER_LDFLAGS'] << '-liperf'
  
  # Add other C flags
  config.build_settings['OTHER_CFLAGS'] ||= ['$(inherited)']
  config.build_settings['OTHER_CFLAGS'] << '-DHAVE_CONFIG_H'
  
  # Set bridging header
  config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'Runner/Runner-Bridging-Header.h'
end

project.save
puts "Successfully added native files to Xcode project"
