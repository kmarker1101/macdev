# frozen_string_literal: true

require 'time'

module Macdev
  # Lock file management for reproducible builds
  class Lock
    attr_reader :metadata, :packages, :dependencies

    def initialize
      @metadata = {
        'generated' => Time.now.utc.iso8601,
        'macdev_version' => VERSION
      }
      @packages = {}
      @dependencies = {}
    end

    # Class methods

    def self.load
      return nil unless File.exist?(Manifest::LOCK_FILE)

      begin
        data = TomlRB.load_file(Manifest::LOCK_FILE)
        lock = allocate
        lock.instance_variable_set(:@metadata, data['metadata'] || {})
        lock.instance_variable_set(:@packages, data['packages'] || {})
        lock.instance_variable_set(:@dependencies, data['dependencies'] || {})
        lock
      rescue StandardError => e
        warn "Warning: Failed to load #{Manifest::LOCK_FILE}: #{e.message}"
        nil
      end
    end

    def self.exists?
      File.exist?(Manifest::LOCK_FILE)
    end

    def self.generate
      local_manifest = Manifest.load(Manifest::MANIFEST_FILE)
      return unless local_manifest

      packages = local_manifest.packages

      if packages.nil? || packages.empty?
        FileUtils.rm_f(Manifest::LOCK_FILE)
        return
      end

      puts "  \e[34m→\e[0m Generating lock file..."

      lock = new
      packages.each do |name, version|
        lock_package_with_deps(lock, name, version)
      end

      lock.save
      puts "  \e[32m✓\e[0m Lock file saved"
    rescue StandardError => e
      warn "Warning: Failed to generate lock file: #{e.message}" if ENV['DEBUG']
    end

    private_class_method def self.lock_package_with_deps(lock, name, version)
      spec = version == '*' ? name : "#{name}@#{version}"
      info = Homebrew.package_info(spec)
      return unless info

      lock.add_package(name, info[:version], info[:formula])
      puts "    Locked #{name} @ #{info[:version]}"

      lock_package_dependencies(lock, name, spec)
    end

    private_class_method def self.lock_package_dependencies(lock, name, spec)
      deps = Homebrew.package_deps(spec)
      return if deps.empty?

      puts "      Locking #{deps.length} dependencies..."
      deps.each do |dep|
        dep_info = Homebrew.package_info(dep)
        next unless dep_info

        lock.add_dependency(name, dep, dep_info[:version], dep_info[:formula])
      end
    end

    # Instance methods

    def save
      FileUtils.mkdir_p(File.dirname(Manifest::LOCK_FILE))

      data = {
        'metadata' => @metadata,
        'packages' => @packages,
        'dependencies' => @dependencies
      }.reject { |k, v| k != 'metadata' && v.empty? }

      File.write(Manifest::LOCK_FILE, TomlRB.dump(data))
    end

    def add_package(name, version, formula)
      @packages[name] = {
        'version' => version,
        'formula' => formula
      }
    end

    def add_dependency(package, dep, version, formula)
      key = "#{package}:#{dep}"
      @dependencies[key] = {
        'version' => version,
        'formula' => formula
      }
    end
  end
end
