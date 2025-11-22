# frozen_string_literal: true

require 'English'

module Macdev
  # Homebrew package manager integration
  class Homebrew
    def self.installed?
      system('which brew > /dev/null 2>&1')
    end

    def self.install(package, link: true)
      # Install the package normally
      system('brew', 'install', package) || abort("\e[31mFailed to install #{package}\e[0m")

      # If we don't want it linked (pure package), unlink it after install
      unlink(package) unless link

      # Return the install path
      prefix(package)
    end

    def self.install_cask(package)
      system('brew', 'install', '--cask', package) ||
        abort("\e[31mFailed to install cask #{package}\e[0m")
    end

    def self.prefix(package)
      output = `brew --prefix #{package} 2>/dev/null`.strip
      return nil if output.empty? || $CHILD_STATUS.exitstatus != 0

      output
    end

    def self.unlink(package)
      system('brew', 'unlink', package, out: File::NULL, err: File::NULL)
    end

    def self.package_installed?(package)
      system("brew list #{package} > /dev/null 2>&1")
    end

    def self.uninstall_package(package)
      output = `brew uninstall #{package} 2>&1`
      success = $CHILD_STATUS.exitstatus.zero?

      puts "    \e[33m⚠\e[0m Failed to uninstall: #{output.strip}" unless success

      success
    end

    def self.uninstall_cask(cask)
      output = `brew uninstall --cask #{cask} 2>&1`
      success = $CHILD_STATUS.exitstatus.zero?

      puts "    \e[33m⚠\e[0m Failed to uninstall: #{output.strip}" unless success

      success
    end

    def self.cask_installed?(cask)
      system("brew list --cask #{cask} > /dev/null 2>&1")
    end

    def self.cleanup
      system('brew', 'cleanup')
    end

    def self.tap_tapped?(tap)
      system("brew tap | grep -q '^#{tap}$'")
    end

    def self.tap(tap)
      system('brew', 'tap', tap) || abort("\e[31mFailed to tap #{tap}\e[0m")
    end

    def self.untap(tap)
      system('brew', 'untap', tap) || abort("\e[31mFailed to untap #{tap}\e[0m")
    end

    def self.package_info(package)
      require 'json'

      output = `brew info --json=v2 #{package} 2>&1`
      return nil if $CHILD_STATUS.exitstatus != 0

      begin
        data = JSON.parse(output)
        formulae = data['formulae']
        return nil if formulae.nil? || formulae.empty?

        formula = formulae[0]
        {
          version: formula['versions']['stable'],
          formula: formula['full_name']
        }
      rescue JSON::ParserError, NoMethodError
        nil
      end
    end

    def self.package_deps(package)
      output = `brew deps --formula #{package} 2>&1`
      return [] if $CHILD_STATUS.exitstatus != 0

      output.lines.map(&:strip).reject(&:empty?)
    end
  end
end
