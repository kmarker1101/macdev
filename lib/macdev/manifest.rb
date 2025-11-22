# frozen_string_literal: true

module Macdev
  # Package manifest management
  class Manifest
    MANIFEST_FILE = 'macdev.toml'
    GLOBAL_MANIFEST = File.expand_path('~/.config/macdev/macdev.toml')
    LOCK_FILE = 'macdev.lock'

    attr_reader :packages, :impure, :casks, :gc, :taps

    def initialize(packages: {}, impure: {}, casks: {}, garbage_collect: {}, taps: {})
      @packages = packages
      @impure = impure
      @casks = casks
      @gc = garbage_collect
      @taps = taps
    end

    # Class methods for initialization and loading

    def self.init
      if File.exist?(MANIFEST_FILE)
        puts "\e[33mManifest already exists\e[0m"
        return
      end

      manifest = new
      manifest.save(MANIFEST_FILE)

      puts "\e[32m✓ Initialized macdev environment\e[0m"
      puts "  Created #{MANIFEST_FILE}"
    end

    def self.load(path)
      return nil unless File.exist?(path)

      begin
        data = TomlRB.load_file(path)
        new(
          packages: data['packages'] || {},
          impure: data['impure'] || {},
          casks: data['casks'] || {},
          garbage_collect: data['gc'] || {},
          taps: data['taps'] || {}
        )
      rescue StandardError => e
        warn "Warning: Failed to load #{path}: #{e.message}"
        nil
      end
    end

    def self.load_or_create_global
      if File.exist?(GLOBAL_MANIFEST)
        load(GLOBAL_MANIFEST) || new
      else
        FileUtils.mkdir_p(File.dirname(GLOBAL_MANIFEST))
        new
      end
    end

    def self.list
      local = load(MANIFEST_FILE)
      global = load(GLOBAL_MANIFEST)

      has_local = local && !local.packages.empty?
      has_pure = global && !global.packages.empty?
      has_impure = global && !global.impure.empty?
      has_casks = global && !global.casks.empty?

      unless has_local || has_pure || has_impure || has_casks
        puts "\e[33mNo packages, casks, or taps installed\e[0m"
        return
      end

      display_local_packages(local) if has_local
      display_pure_packages(global) if has_pure
      display_impure_packages(global) if has_impure
      display_casks(global) if has_casks
    end

    private_class_method def self.display_local_packages(local)
      puts "\e[34m\e[1mProject packages (from macdev.toml):\e[0m"
      local.packages.each do |name, version|
        if version == '*'
          puts "  #{name}"
        else
          puts "  #{name}@#{version}"
        end
      end
      puts
    end

    private_class_method def self.display_pure_packages(global)
      global_path = GLOBAL_MANIFEST.gsub(Dir.home, '~')
      puts "\e[32m\e[1mPure packages (from #{global_path}):\e[0m"
      global.packages.each do |name, version|
        if name.include?('@')
          puts "  #{name}"
        else
          puts "  #{name}@#{version}"
        end
      end
      puts
    end

    private_class_method def self.display_impure_packages(global)
      global_path = GLOBAL_MANIFEST.gsub(Dir.home, '~')
      puts "\e[36m\e[1mImpure packages (from #{global_path}):\e[0m"
      global.impure.each_key do |name|
        puts "  #{name}"
      end
      puts
    end

    private_class_method def self.display_casks(global)
      global_path = GLOBAL_MANIFEST.gsub(Dir.home, '~')
      puts "\e[35m\e[1mCasks (from #{global_path}):\e[0m"
      global.casks.each_key do |name|
        puts "  #{name}"
      end
    end

    # Instance methods for manipulation

    def save(path)
      # For local manifest, only save packages section
      data = if path == MANIFEST_FILE
               { 'packages' => @packages }
             else
               {
                 'packages' => @packages,
                 'impure' => @impure,
                 'casks' => @casks,
                 'gc' => @gc,
                 'taps' => @taps
               }.reject { |k, v| (k == 'packages' && v.empty?) || (k != 'packages' && v.empty?) }
             end

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, TomlRB.dump(data))
    end

    def save_global
      save(GLOBAL_MANIFEST)
    end

    def add_package(name, version)
      @packages[name] = version
    end

    def add_impure(name)
      @impure[name] = true
    end

    def add_cask(name)
      @casks[name] = true
    end

    def remove_package(name)
      @packages.delete(name)
    end

    def remove_impure(name)
      @impure.delete(name)
    end

    def remove_cask(name)
      @casks.delete(name)
    end

    def add_tap(name)
      @taps[name] = true
    end

    def remove_tap(name)
      @taps.delete(name)
    end

    def add_to_gc(name, version)
      @gc[name] = version
    end

    def remove_from_gc(name)
      @gc.delete(name)
    end
  end
end
