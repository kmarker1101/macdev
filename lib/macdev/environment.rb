# frozen_string_literal: true

require 'English'
require 'fileutils'
require 'toml-rb'

module Macdev
  # Core environment operations (add, remove, install, etc.)
  class Environment
    def self.add(package_spec, impure: false, cask: false)
      # Check Homebrew is installed
      abort "\e[31mHomebrew is not installed. Install it from https://brew.sh\e[0m" unless Homebrew.installed?

      return add_cask(package_spec, impure) if cask

      # For pure packages, check that manifest exists BEFORE installing anything
      if !impure && !File.exist?(Manifest::MANIFEST_FILE)
        abort "\e[31mNo manifest found. Run 'macdev init' first to initialize the environment.\e[0m"
      end

      package, version = parse_package_spec(package_spec)
      global_manifest = Manifest.load_or_create_global
      name = package.split('@').first
      manifest_key, manifest_value = build_manifest_keys(package, version, name)

      prepare_package_for_add(global_manifest, name, version)

      if impure
        add_impure_package(package, manifest_key, global_manifest)
      else
        add_pure_package(package, name, version, manifest_key, manifest_value, global_manifest)
      end
    end

    def self.install
      # Load manifests
      local_manifest = Manifest.load(Manifest::MANIFEST_FILE)
      abort "\e[31mNo manifest found. Run 'macdev init' first.\e[0m" unless local_manifest

      global_manifest = Manifest.load_or_create_global

      puts "\e[36m\e[1mInstalling packages from manifest...\e[0m"

      # Install pure packages from local manifest (no link)
      has_python = false
      if local_manifest.packages && !local_manifest.packages.empty?
        local_manifest.packages.each do |name, version|
          install_package(name, version, global_manifest)
          has_python = true if name == 'python'
        end

        # Save global manifest with newly installed pure packages
        global_manifest.save_global

        # Special Python handling if Python was installed
        if has_python
          normalize_python_symlinks
          setup_python_venv
        end
      else
        puts "  \e[33mNo packages in manifest\e[0m"
      end

      puts "\e[32m✓\e[0m All packages installed"

      # Generate lock file after installation
      Lock.generate
    end

    def self.remove(package)
      package_base = package.split('@').first
      local_manifest = Manifest.load(Manifest::MANIFEST_FILE)
      global_manifest = Manifest.load_or_create_global

      return remove_cask(package, global_manifest) if global_manifest.casks && global_manifest.casks[package]

      is_impure = determine_package_type(package, package_base, global_manifest)

      puts "\e[33mRemoving\e[0m #{package} from environment"

      if is_impure
        remove_impure_package(package, package_base, global_manifest)
      else
        remove_pure_package(package, package_base, local_manifest, global_manifest)
      end

      Lock.generate
    end

    def self.gc(all = false)
      global_manifest = Manifest.load_or_create_global
      has_gc = global_manifest.gc && !global_manifest.gc.empty?
      has_pure = global_manifest.packages && !global_manifest.packages.empty?

      if !has_gc && (!all || !has_pure)
        puts "\e[33mNo packages to garbage collect\e[0m"
        return
      end

      puts "\e[36m\e[1mGarbage collecting unused packages...\e[0m"
      puts

      to_remove = has_gc ? gc_packages(global_manifest) : []
      gc_all_pure_packages(global_manifest) if all

      global_manifest.save_global

      puts
      puts "\e[32m✓\e[0m Uninstalled #{to_remove.length} package(s)" unless to_remove.empty?

      puts
      puts "\e[36mRunning brew cleanup...\e[0m"
      Homebrew.cleanup

      Lock.generate
    end

    def self.sync
      local_manifest = Manifest.load(Manifest::MANIFEST_FILE)
      global_manifest = Manifest.load_or_create_global

      puts "\e[36m\e[1mSyncing packages from manifest(s)...\e[0m"
      puts

      synced_count = 0
      synced_count += sync_taps(global_manifest)
      synced_count += sync_pure_packages(local_manifest, global_manifest)
      synced_count += sync_impure_packages(global_manifest)

      puts
      if synced_count.positive?
        puts "\e[32m✓\e[0m Synced #{synced_count} item(s)"
      else
        puts "\e[33mAll items already synced\e[0m"
      end
    end

    def self.check(quiet = false)
      # Check if manifest exists
      unless File.exist?(Manifest::MANIFEST_FILE)
        warn "No manifest found. Run 'macdev init' first." unless quiet
        exit 1
      end

      local_manifest = Manifest.load(Manifest::MANIFEST_FILE)
      global_manifest = Manifest.load_or_create_global

      check_missing_packages(local_manifest, global_manifest, quiet)
      check_profile_directory(quiet)

      # Generate lock file if it doesn't exist
      Lock.generate unless Lock.exists?

      puts 'Environment is set up' unless quiet
    end

    def self.upgrade(package = nil)
      local_manifest = Manifest.load(Manifest::MANIFEST_FILE)
      global_manifest = Manifest.load_or_create_global

      if package
        upgrade_specific_package(package, local_manifest, global_manifest)
      else
        upgrade_all_packages(local_manifest, global_manifest)
      end

      Lock.generate
    end

    def self.shell
      # Only run install if not already in a macdev shell (avoid conflicts)
      if ENV['MACDEV_ACTIVE'].nil?
        puts "\e[36mEnsuring environment is up to date...\e[0m"
        install
        puts
      end

      profile_dir = '.macdev/profile'

      # Build PATH with profile/bin at the front
      profile_bin = File.expand_path(File.join(profile_dir, 'bin'))
      abort "\e[31mProfile directory not found. Run 'macdev install' first.\e[0m" unless Dir.exist?(profile_bin)

      current_path = ENV['PATH'] || ''
      new_path = "#{profile_bin}:#{current_path}"

      # Get current shell
      shell = ENV['SHELL'] || '/bin/bash'

      puts "\e[36mEntering macdev environment...\e[0m"
      puts "  Shell: \e[90m#{shell}\e[0m"
      puts "  Type 'exit' to leave"
      puts

      # Spawn shell with modified PATH
      exec(
        { 'PATH' => new_path, 'MACDEV_ACTIVE' => '1' },
        shell
      )
    end

    def self.tap(tap_name)
      # Check Homebrew is installed
      abort "\e[31mHomebrew is not installed. Install it from https://brew.sh\e[0m" unless Homebrew.installed?

      global_manifest = Manifest.load_or_create_global

      # Check if already tapped and tracked
      if global_manifest.taps && global_manifest.taps[tap_name]
        puts "\e[33m⚠ Tap '#{tap_name}' is already tracked\e[0m"
        return
      end

      puts "\e[32mAdding tap\e[0m #{tap_name}"

      # Add the tap if not already tapped
      if Homebrew.tap_tapped?(tap_name)
        puts '  Tap already exists in Homebrew'
      else
        Homebrew.tap(tap_name)
      end

      # Track in global manifest
      global_manifest.add_tap(tap_name)
      global_manifest.save_global

      global_path = Manifest::GLOBAL_MANIFEST.gsub(Dir.home, '~')
      puts "\e[32m✓\e[0m Tap added (saved to #{global_path})"
    end

    def self.untap(tap_name)
      global_manifest = Manifest.load_or_create_global

      # Check if tap exists in manifest
      abort "\e[31mTap '#{tap_name}' is not tracked\e[0m" unless global_manifest.taps && global_manifest.taps[tap_name]

      puts "\e[33mRemoving tap\e[0m #{tap_name}"

      # Remove from Homebrew
      Homebrew.untap(tap_name) if Homebrew.tap_tapped?(tap_name)

      # Remove from global manifest
      global_manifest.remove_tap(tap_name)
      global_manifest.save_global

      puts "\e[32m✓\e[0m Tap removed"
    end

    def self.rebuild_profile(manifest)
      profile_dir = '.macdev/profile'

      # Delete entire profile directory
      FileUtils.rm_rf(profile_dir)

      # Recreate symlinks for all remaining pure packages
      return unless manifest.packages && !manifest.packages.empty?

      puts '  Rebuilding environment...'

      manifest.packages.each do |name, version|
        spec = if version == '*'
                 name
               else
                 "#{name}@#{version}"
               end

        brew_path = Homebrew.prefix(spec)
        create_symlinks(spec, brew_path) if brew_path
      end
    end

    def self.parse_package_spec(spec)
      if spec.include?('@') && spec.rindex('@').positive?
        idx = spec.rindex('@')
        version = spec[(idx + 1)..]
        [spec, version]
      else
        [spec, nil]
      end
    end

    def self.create_symlinks(_package, prefix)
      profile_bin = '.macdev/profile/bin'
      FileUtils.mkdir_p(profile_bin)

      # Look for binaries in common locations
      ['bin', 'libexec/bin'].each do |subdir|
        source_dir = File.join(prefix, subdir)
        next unless Dir.exist?(source_dir)

        Dir.glob(File.join(source_dir, '*')).each do |source_file|
          next unless File.file?(source_file) || File.symlink?(source_file)

          basename = File.basename(source_file)
          target = File.join(profile_bin, basename)

          # Remove existing symlink if present
          File.delete(target) if File.exist?(target) || File.symlink?(target)

          # Create symlink
          File.symlink(source_file, target)
        end
      end
    end

    # Private helper methods for add command
    class << self
      private

      def add_cask(package_spec, impure)
        puts "\e[33mNote: Casks are always installed system-wide (impure)\e[0m" unless impure

        global_manifest = Manifest.load_or_create_global

        puts "\e[32mAdding\e[0m #{package_spec} (cask)"
        Homebrew.install_cask(package_spec)

        global_manifest.add_cask(package_spec)
        global_manifest.save_global

        global_path = Manifest::GLOBAL_MANIFEST.gsub(Dir.home, '~')
        puts "\e[32m✓\e[0m Cask installed system-wide (saved to #{global_path})"
      end

      def build_manifest_keys(_package, version, name)
        if version
          [name, version]
        else
          [name, '*']
        end
      end

      def prepare_package_for_add(global_manifest, name, version)
        if global_manifest.gc && global_manifest.gc[name]
          global_manifest.remove_from_gc(name)
          puts '  Package was in gc, restoring...'
        end

        global_manifest.remove_package(name) if version
      end

      def add_impure_package(package, manifest_key, global_manifest)
        puts "\e[32mAdding\e[0m #{package} (impure)"
        Homebrew.install(package, link: true)

        global_manifest.add_impure(manifest_key)
        global_manifest.save_global

        global_path = Manifest::GLOBAL_MANIFEST.gsub(Dir.home, '~')
        puts "\e[32m✓\e[0m Package available system-wide (saved to #{global_path})"
      end

      def add_pure_package(package, name, version, manifest_key, manifest_value, global_manifest)
        puts "\e[32mAdding\e[0m #{package} (pure)"
        brew_path = Homebrew.install(package, link: false)

        create_symlinks(package, brew_path)

        # Special handling for Python: normalize symlinks and create venv
        if name == 'python' || package.start_with?('python@')
          normalize_python_symlinks
          setup_python_venv
        end

        ver = version || '*'

        local_manifest = Manifest.load(Manifest::MANIFEST_FILE)
        local_manifest.add_package(name, ver)
        local_manifest.save(Manifest::MANIFEST_FILE)

        global_manifest.add_package(manifest_key, manifest_value)
        global_manifest.save_global

        puts "\e[32m✓\e[0m Package isolated to this project"

        Lock.generate
      end

      # Private helper methods for install command
      def install_package(name, version, global_manifest)
        spec = if version == '*'
                 name
               else
                 "#{name}@#{version}"
               end

        puts "  \e[34m→\e[0m #{spec}"

        brew_path = Homebrew.install(spec, link: false)
        create_symlinks(spec, brew_path)

        manifest_key = version == '*' ? name : "#{name}@#{version}"
        global_manifest.add_package(manifest_key, '*')
      end

      # Private helper methods for check command
      def check_missing_packages(local_manifest, global_manifest, quiet)
        missing = []
        local_manifest&.packages&.each_key do |name|
          missing << name unless global_manifest.packages && global_manifest.packages[name]
        end

        return if missing.empty?

        unless quiet
          warn "Missing packages: #{missing.join(', ')}"
          warn "Run 'macdev install' to set up."
        end
        exit 1
      end

      def check_profile_directory(quiet)
        profile_bin = '.macdev/profile/bin'
        return if Dir.exist?(profile_bin) && !Dir.empty?(profile_bin)

        warn "Profile directory empty. Run 'macdev install'." unless quiet
        exit 1
      end

      # Private helper methods for remove command
      def remove_cask(package, global_manifest)
        puts "\e[33mRemoving\e[0m #{package} from environment"
        global_manifest.remove_cask(package)
        global_manifest.save_global

        puts "\e[32m✓\e[0m Cask #{package} removed (moved to gc)"

        global_manifest.add_to_gc(package, '*')
        global_manifest.save_global
      end

      def package_exists_in_manifest?(manifest_section, package, _package_base)
        manifest_section && manifest_section[package]
      end

      def determine_package_type(package, package_base, global_manifest)
        has_version = package.include?('@')

        exact_pure = package_exists_in_manifest?(global_manifest.packages, package, package)
        exact_impure = package_exists_in_manifest?(global_manifest.impure, package, package)
        base_pure = package_exists_in_manifest?(global_manifest.packages, package_base, package_base)
        base_impure = package_exists_in_manifest?(global_manifest.impure, package_base, package_base)

        unless exact_pure || exact_impure || base_pure || base_impure
          abort "\e[31mPackage '#{package}' is not tracked globally\e[0m"
        end

        if has_version
          exact_impure || (!exact_pure && !base_pure && base_impure)
        else
          exact_impure || (!exact_pure && base_impure)
        end
      end

      def remove_impure_package(package, package_base, global_manifest)
        removed = if global_manifest.impure && global_manifest.impure[package]
                    global_manifest.remove_impure(package)
                    true
                  elsif global_manifest.impure && global_manifest.impure[package_base]
                    global_manifest.remove_impure(package_base)
                    true
                  else
                    false
                  end

        return unless removed

        gc_key = package.include?('@') ? package : package_base
        global_manifest.add_to_gc(gc_key, '*')
        global_manifest.save_global
        puts "\e[32m✓\e[0m Removed #{package} (impure, moved to gc)"
      end

      def remove_pure_package(package, package_base, local_manifest, global_manifest)
        pkg_key = if local_manifest&.packages && local_manifest.packages[package]
                    package
                  else
                    package_base
                  end

        if local_manifest&.packages && local_manifest.packages[pkg_key]
          local_manifest.remove_package(pkg_key)
          local_manifest.save(Manifest::MANIFEST_FILE)
          rebuild_profile(local_manifest)
          puts '  Removed from local project manifest'
        end

        removed_key, version = remove_from_global_packages(package, package_base, global_manifest)

        global_manifest.add_to_gc(removed_key, version) if removed_key
        global_manifest.save_global
        puts "\e[32m✓\e[0m Removed #{package} (moved to gc)"
      end

      def remove_from_global_packages(package, package_base, global_manifest)
        if global_manifest.packages && global_manifest.packages[package]
          version = global_manifest.packages[package]
          global_manifest.remove_package(package)
          [package, version]
        elsif global_manifest.packages && global_manifest.packages[package_base]
          version = global_manifest.packages[package_base]
          global_manifest.remove_package(package_base)
          # Reconstruct the full package spec for gc
          gc_key = version == '*' ? package_base : "#{package_base}@#{version}"
          [gc_key, version]
        else
          [nil, nil]
        end
      end

      # Private helper methods for gc command
      def gc_packages(global_manifest)
        to_remove = []

        global_manifest.gc.each_key do |name|
          puts "  \e[31mUninstalling\e[0m #{name}"

          result = if Homebrew.cask_installed?(name)
                     Homebrew.uninstall_cask(name)
                   else
                     Homebrew.uninstall_package(name)
                   end

          if result
            to_remove << name
          else
            puts "    \e[33m⚠\e[0m Keeping in gc for next run"
          end
        end

        to_remove.each { |name| global_manifest.remove_from_gc(name) }
        to_remove
      end

      def gc_all_pure_packages(global_manifest)
        puts
        puts "\e[36mRemoving all pure packages...\e[0m"

        return unless global_manifest.packages

        pure_packages = global_manifest.packages.keys.dup
        pure_packages.each do |name|
          puts "  \e[31mUninstalling\e[0m #{name}"
          global_manifest.remove_package(name) if Homebrew.uninstall_package(name)
        end
      end

      # Private helper methods for sync command
      def sync_taps(global_manifest)
        return 0 unless global_manifest.taps && !global_manifest.taps.empty?

        puts "\e[35mSyncing taps from global manifest:\e[0m"
        synced_count = 0

        global_manifest.taps.each_key do |tap_name|
          if Homebrew.tap_tapped?(tap_name)
            puts "  \e[32m✓\e[0m #{tap_name} (already tapped)"
          else
            puts "  \e[34m→\e[0m #{tap_name}"
            Homebrew.tap(tap_name)
            synced_count += 1
          end
        end
        puts

        synced_count
      end

      def sync_pure_packages(local_manifest, global_manifest)
        return 0 unless local_manifest&.packages && !local_manifest.packages.empty?

        puts "\e[32mSyncing pure packages from local manifest:\e[0m"
        synced_count = 0

        local_manifest.packages.each do |name, version|
          if global_manifest.packages && global_manifest.packages[name]
            puts "  \e[32m✓\e[0m #{name} (already installed)"
          else
            spec = version == '*' ? name : "#{name}@#{version}"
            puts "  \e[34m→\e[0m #{spec}"
            add(spec, impure: false, cask: false)
            synced_count += 1
          end
        end
        puts

        synced_count
      end

      def sync_impure_packages(global_manifest)
        return 0 unless global_manifest.impure && !global_manifest.impure.empty?

        puts "\e[36mSyncing impure packages from global manifest:\e[0m"
        synced_count = 0

        global_manifest.impure.each_key do |name|
          if Homebrew.package_installed?(name)
            puts "  \e[32m✓\e[0m #{name} (already installed)"
          else
            puts "  \e[34m→\e[0m #{name}"
            add(name, impure: true, cask: false)
            synced_count += 1
          end
        end

        synced_count
      end

      # Private helper methods for upgrade command
      def upgrade_specific_package(package, local_manifest, global_manifest)
        puts "\e[36mUpgrading\e[0m #{package}"

        pkg_base = package.split('@').first
        is_pure = local_manifest&.packages && local_manifest.packages[pkg_base]
        is_impure = global_manifest.impure && global_manifest.impure[pkg_base]

        abort "\e[31mPackage '#{package}' is not managed by macdev\e[0m" unless is_pure || is_impure

        abort "\e[31mFailed to upgrade #{package}\e[0m" unless system('brew', 'upgrade', package)

        handle_pure_package_upgrade(package, pkg_base, local_manifest) if is_pure

        puts "\e[32m✓\e[0m Upgraded #{package}"
      end

      def handle_pure_package_upgrade(package, pkg_base, local_manifest)
        puts '  Rebuilding profile...'
        rebuild_profile(local_manifest) if local_manifest

        return unless pkg_base == 'python' || package.start_with?('python@')

        puts
        puts "  \e[36mℹ\e[0m Python was upgraded. You may want to recreate the venv:"
        puts '    rm -rf .macdev/venv'
        puts '    macdev install'
      end

      def upgrade_all_packages(local_manifest, global_manifest)
        puts "\e[36m\e[1mUpgrading all managed packages...\e[0m"
        puts

        python_upgraded, pure_count = upgrade_pure_packages(local_manifest)
        impure_count = upgrade_impure_packages(global_manifest)

        finalize_upgrade(local_manifest, python_upgraded, pure_count + impure_count)
      end

      def upgrade_pure_packages(local_manifest)
        return [false, 0] unless local_manifest&.packages && !local_manifest.packages.empty?

        puts "\e[32mUpgrading pure packages:\e[0m"
        upgraded_count = 0
        python_upgraded = false

        local_manifest.packages.each do |name, version|
          spec = version == '*' ? name : "#{name}@#{version}"
          puts "  \e[34m→\e[0m #{spec}"

          output = `brew upgrade #{spec} 2>&1`
          success = $CHILD_STATUS.exitstatus.zero?

          next unless success && !output.include?('already installed')

          upgraded_count += 1
          python_upgraded = true if name == 'python' || spec.start_with?('python@')
        end
        puts

        [python_upgraded, upgraded_count]
      end

      def upgrade_impure_packages(global_manifest)
        return 0 unless global_manifest.impure && !global_manifest.impure.empty?

        puts "\e[36mUpgrading impure packages:\e[0m"
        upgraded_count = 0

        global_manifest.impure.each_key do |name|
          puts "  \e[34m→\e[0m #{name}"
          output = `brew upgrade #{name} 2>&1`
          success = $CHILD_STATUS.exitstatus.zero?

          upgraded_count += 1 if success && !output.include?('already installed')
        end
        puts

        upgraded_count
      end

      def finalize_upgrade(local_manifest, python_upgraded, upgraded_count)
        if local_manifest&.packages && !local_manifest.packages.empty?
          puts 'Rebuilding profile...'
          rebuild_profile(local_manifest)
        end

        if python_upgraded
          puts
          puts "  \e[36mℹ\e[0m Python was upgraded. You may want to recreate the venv:"
          puts '    rm -rf .macdev/venv'
          puts '    macdev install'
        end

        puts
        puts "\e[32m✓\e[0m Upgraded #{upgraded_count} package(s)"
      end

      def normalize_python_symlinks
        bin_dir = '.macdev/profile/bin'
        return warn 'Profile bin directory does not exist' unless Dir.exist?(bin_dir)

        versioned_name = find_versioned_python_binary(bin_dir)
        return unless versioned_name

        puts "  Found Python binary: #{versioned_name}"

        create_symlink_in_dir(bin_dir, 'python3', versioned_name)
        create_symlink_in_dir(bin_dir, 'python', versioned_name)
        normalize_pip_symlinks(bin_dir, versioned_name)

        puts "  \e[32m✓\e[0m Normalized python and pip symlinks"
      end

      def find_versioned_python_binary(bin_dir)
        versioned_python = Dir.glob(File.join(bin_dir, 'python3.*')).find do |path|
          basename = File.basename(path)
          basename.start_with?('python3.') && !basename.include?('-config')
        end

        if versioned_python
          File.basename(versioned_python)
        else
          warn 'Could not find versioned Python binary (python3.X) in profile/bin'
          nil
        end
      end

      def create_symlink_in_dir(dir, link_name, target)
        link_path = File.join(dir, link_name)
        File.delete(link_path) if File.exist?(link_path) || File.symlink?(link_path)
        File.symlink(target, link_path)
      end

      def normalize_pip_symlinks(bin_dir, versioned_python)
        version_match = versioned_python.match(/python3\.(\d+)/)
        return unless version_match

        pip_version = "pip3.#{version_match[1]}"
        versioned_pip = File.join(bin_dir, pip_version)
        return unless File.exist?(versioned_pip)

        create_symlink_in_dir(bin_dir, 'pip3', pip_version)
        create_symlink_in_dir(bin_dir, 'pip', pip_version)
      end

      def setup_python_venv
        venv_dir = '.macdev/venv'

        # Skip if venv already exists
        if Dir.exist?(venv_dir)
          puts "  \e[32m✓\e[0m Python venv already exists"
          return
        end

        puts "  \e[34m→\e[0m Creating Python virtual environment..."

        # Get python3 from the profile
        python_bin = '.macdev/profile/bin/python3'
        unless File.exist?(python_bin)
          warn 'Python binary not found in profile'
          return
        end

        # Create venv
        success = system(python_bin, '-m', 'venv', venv_dir)

        unless success
          warn 'Failed to create Python virtual environment'
          return
        end

        puts "  \e[32m✓\e[0m Python venv created at .macdev/venv"
        puts
        puts "  \e[36mℹ\e[0m  To activate, add to your shell or use direnv"
      end
    end
  end
end
