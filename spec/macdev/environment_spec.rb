# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Macdev::Environment do
  let(:tmpdir) { Dir.mktmpdir }
  let(:manifest_file) { File.join(tmpdir, 'macdev.toml') }
  let(:global_manifest_file) { File.join(tmpdir, '.config/macdev/macdev.toml') }
  let(:profile_dir) { File.join(tmpdir, '.macdev/profile') }

  before do
    # Stub file paths to use tmpdir
    stub_const('Macdev::Manifest::MANIFEST_FILE', manifest_file)
    stub_const('Macdev::Manifest::GLOBAL_MANIFEST', global_manifest_file)

    # Mock all Homebrew calls - NEVER call real brew
    allow(Macdev::Homebrew).to receive(:installed?).and_return(true)
    allow(Macdev::Homebrew).to receive(:install).and_return('/fake/homebrew/opt/package')
    allow(Macdev::Homebrew).to receive(:prefix).and_return('/fake/homebrew/opt/package')
    allow(Macdev::Homebrew).to receive(:package_installed?).and_return(false)
    allow(Macdev::Homebrew).to receive(:unlink)
    allow(Macdev::Homebrew).to receive(:cleanup)

    # Mock Lock operations
    allow(Macdev::Lock).to receive(:generate)
    allow(Macdev::Lock).to receive(:exists?).and_return(false)

    # Create initial manifest
    FileUtils.mkdir_p(File.dirname(manifest_file))
    Macdev::Manifest.new.save(manifest_file)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe '.add' do
    context 'when adding a pure package' do
      before do
        # Mock create_symlinks to avoid filesystem operations
        allow(described_class).to receive(:create_symlinks)
      end

      it 'adds package to local and global manifests' do
        described_class.add('rust', impure: false, cask: false)

        local = Macdev::Manifest.load(manifest_file)
        global = Macdev::Manifest.load(global_manifest_file)

        expect(local.packages).to include('rust' => '*')
        expect(global.packages).to include('rust' => '*')
      end

      it 'calls Homebrew.install without linking' do
        expect(Macdev::Homebrew).to receive(:install).with('rust', link: false)

        described_class.add('rust', impure: false, cask: false)
      end

      it 'generates lock file after adding' do
        expect(Macdev::Lock).to receive(:generate)

        described_class.add('rust', impure: false, cask: false)
      end

      it 'handles versioned packages' do
        described_class.add('python@3.11', impure: false, cask: false)

        local = Macdev::Manifest.load(manifest_file)

        expect(local.packages).to include('python' => '3.11')
      end
    end

    context 'when adding an impure package' do
      it 'adds package to global manifest impure section' do
        described_class.add('git', impure: true, cask: false)

        global = Macdev::Manifest.load(global_manifest_file)

        expect(global.impure).to include('git' => true)
      end

      it 'calls Homebrew.install with linking' do
        expect(Macdev::Homebrew).to receive(:install).with('git', link: true)

        described_class.add('git', impure: true, cask: false)
      end

      it 'does not generate lock file for impure packages' do
        expect(Macdev::Lock).not_to receive(:generate)

        described_class.add('git', impure: true, cask: false)
      end
    end

    context 'when adding a cask' do
      it 'adds cask to global manifest' do
        allow(Macdev::Homebrew).to receive(:install_cask)

        described_class.add('firefox', impure: false, cask: true)

        global = Macdev::Manifest.load(global_manifest_file)

        expect(global.casks).to include('firefox' => true)
      end
    end

    context 'when manifest does not exist' do
      before do
        FileUtils.rm_f(manifest_file)
      end

      it 'aborts for pure packages' do
        expect do
          described_class.add('rust', impure: false, cask: false)
        end.to raise_error(SystemExit)
      end

      it 'allows impure packages' do
        expect do
          described_class.add('git', impure: true, cask: false)
        end.not_to raise_error
      end
    end
  end

  describe '.install' do
    before do
      # Create a manifest with packages
      manifest = Macdev::Manifest.new(packages: { 'rust' => '*', 'python' => '3.11' })
      manifest.save(manifest_file)

      # Mock create_symlinks
      allow(described_class).to receive(:create_symlinks)
    end

    it 'installs all packages from manifest' do
      expect(Macdev::Homebrew).to receive(:install).with('rust', link: false)
      expect(Macdev::Homebrew).to receive(:install).with('python@3.11', link: false)

      described_class.install
    end

    it 'generates lock file after installation' do
      expect(Macdev::Lock).to receive(:generate)

      described_class.install
    end
  end

  describe '.remove' do
    before do
      # Mock rebuild_profile to avoid filesystem operations
      allow(described_class).to receive(:rebuild_profile)
    end

    context 'when removing a cask' do
      before do
        # Create global manifest with a cask
        global = Macdev::Manifest.new(casks: { 'firefox' => true })
        global.save(global_manifest_file)
      end

      it 'removes cask from global manifest' do
        described_class.remove('firefox')

        global = Macdev::Manifest.load(global_manifest_file)
        expect(global.casks).not_to include('firefox')
      end

      it 'adds cask to garbage collection' do
        described_class.remove('firefox')

        global = Macdev::Manifest.load(global_manifest_file)
        expect(global.gc).to include('firefox' => '*')
      end

      it 'does not call Lock.generate' do
        expect(Macdev::Lock).not_to receive(:generate)

        described_class.remove('firefox')
      end
    end

    context 'when removing an impure package' do
      before do
        # Create global manifest with impure package
        global = Macdev::Manifest.new(impure: { 'git' => true })
        global.save(global_manifest_file)
      end

      it 'removes package from global impure section' do
        described_class.remove('git')

        global = Macdev::Manifest.load(global_manifest_file)
        expect(global.impure).not_to include('git')
      end

      it 'adds package to garbage collection' do
        described_class.remove('git')

        global = Macdev::Manifest.load(global_manifest_file)
        expect(global.gc).to include('git' => '*')
      end

      it 'calls Lock.generate' do
        expect(Macdev::Lock).to receive(:generate)

        described_class.remove('git')
      end
    end

    context 'when removing a pure package' do
      before do
        # Create both local and global manifests with pure package
        local = Macdev::Manifest.new(packages: { 'rust' => '*' })
        local.save(manifest_file)

        global = Macdev::Manifest.new(packages: { 'rust' => '*' })
        global.save(global_manifest_file)
      end

      it 'removes package from local manifest' do
        described_class.remove('rust')

        local = Macdev::Manifest.load(manifest_file)
        expect(local.packages).not_to include('rust')
      end

      it 'removes package from global manifest' do
        described_class.remove('rust')

        global = Macdev::Manifest.load(global_manifest_file)
        expect(global.packages).not_to include('rust')
      end

      it 'adds package to garbage collection' do
        described_class.remove('rust')

        global = Macdev::Manifest.load(global_manifest_file)
        expect(global.gc).to include('rust' => '*')
      end

      it 'calls rebuild_profile' do
        expect(described_class).to receive(:rebuild_profile)

        described_class.remove('rust')
      end

      it 'calls Lock.generate' do
        expect(Macdev::Lock).to receive(:generate)

        described_class.remove('rust')
      end
    end

    context 'when removing a versioned pure package' do
      before do
        # Create manifests with versioned package
        local = Macdev::Manifest.new(packages: { 'python' => '3.11' })
        local.save(manifest_file)

        global = Macdev::Manifest.new(packages: { 'python' => '3.11' })
        global.save(global_manifest_file)
      end

      it 'removes by exact name python@3.11' do
        described_class.remove('python@3.11')

        local = Macdev::Manifest.load(manifest_file)
        global = Macdev::Manifest.load(global_manifest_file)

        expect(local.packages).not_to include('python')
        expect(global.packages).not_to include('python')
      end

      it 'removes by base name python' do
        described_class.remove('python')

        local = Macdev::Manifest.load(manifest_file)
        global = Macdev::Manifest.load(global_manifest_file)

        expect(local.packages).not_to include('python')
        expect(global.packages).not_to include('python')
      end

      it 'adds versioned package to gc with full package spec' do
        described_class.remove('python@3.11')

        global = Macdev::Manifest.load(global_manifest_file)
        expect(global.gc).to include('python@3.11' => '3.11')
        expect(global.gc).not_to include('python')
      end
    end

    context 'when package is not tracked' do
      it 'aborts with error message' do
        expect do
          described_class.remove('nonexistent')
        end.to raise_error(SystemExit)
      end
    end

    context 'when local manifest does not exist but package is in global' do
      before do
        # Only global manifest exists with pure package
        FileUtils.rm_f(manifest_file)

        global = Macdev::Manifest.new(packages: { 'rust' => '*' })
        global.save(global_manifest_file)
      end

      it 'removes package from global manifest only' do
        described_class.remove('rust')

        global = Macdev::Manifest.load(global_manifest_file)
        expect(global.packages).not_to include('rust')
        expect(global.gc).to include('rust' => '*')
      end

      it 'does not create local manifest' do
        described_class.remove('rust')

        expect(File.exist?(manifest_file)).to be false
      end
    end
  end

  describe '.gc' do
    before do
      # Mock Homebrew uninstall methods
      allow(Macdev::Homebrew).to receive(:uninstall_package).and_return(true)
      allow(Macdev::Homebrew).to receive(:uninstall_cask).and_return(true)
      allow(Macdev::Homebrew).to receive(:cask_installed?).and_return(false)
      allow(Macdev::Homebrew).to receive(:cleanup)
    end

    context 'when gc section has packages' do
      before do
        global = Macdev::Manifest.new(garbage_collect: { 'rust' => '*', 'node' => '20' })
        global.save(global_manifest_file)
      end

      it 'uninstalls packages from gc section' do
        expect(Macdev::Homebrew).to receive(:uninstall_package).with('rust')
        expect(Macdev::Homebrew).to receive(:uninstall_package).with('node')

        described_class.gc
      end

      it 'removes uninstalled packages from gc section' do
        described_class.gc

        global = Macdev::Manifest.load(global_manifest_file)
        expect(global.gc).to be_empty
      end

      it 'calls Homebrew.cleanup' do
        expect(Macdev::Homebrew).to receive(:cleanup)

        described_class.gc
      end

      it 'calls Lock.generate' do
        expect(Macdev::Lock).to receive(:generate)

        described_class.gc
      end
    end

    context 'when gc section has casks' do
      before do
        global = Macdev::Manifest.new(garbage_collect: { 'firefox' => true })
        global.save(global_manifest_file)

        allow(Macdev::Homebrew).to receive(:cask_installed?).with('firefox').and_return(true)
      end

      it 'uninstalls casks using uninstall_cask' do
        expect(Macdev::Homebrew).to receive(:uninstall_cask).with('firefox')

        described_class.gc
      end
    end

    context 'when uninstall fails' do
      before do
        global = Macdev::Manifest.new(garbage_collect: { 'rust' => '*', 'node' => '20' })
        global.save(global_manifest_file)

        # Mock rust fails to uninstall
        allow(Macdev::Homebrew).to receive(:uninstall_package).with('rust').and_return(false)
        allow(Macdev::Homebrew).to receive(:uninstall_package).with('node').and_return(true)
      end

      it 'keeps failed packages in gc section' do
        described_class.gc

        global = Macdev::Manifest.load(global_manifest_file)
        expect(global.gc).to include('rust' => '*')
        expect(global.gc).not_to include('node')
      end
    end

    context 'when gc section is empty' do
      before do
        global = Macdev::Manifest.new
        global.save(global_manifest_file)
      end

      it 'does not uninstall anything' do
        expect(Macdev::Homebrew).not_to receive(:uninstall_package)
        expect(Macdev::Homebrew).not_to receive(:uninstall_cask)

        described_class.gc
      end

      it 'does not call cleanup or Lock.generate' do
        expect(Macdev::Homebrew).not_to receive(:cleanup)
        expect(Macdev::Lock).not_to receive(:generate)

        described_class.gc
      end
    end

    context 'when gc(all: true)' do
      before do
        global = Macdev::Manifest.new(
          packages: { 'rust' => '*', 'python' => '3.11' },
          garbage_collect: { 'node' => '20' }
        )
        global.save(global_manifest_file)
      end

      it 'uninstalls gc packages and all pure packages' do
        expect(Macdev::Homebrew).to receive(:uninstall_package).with('node')
        expect(Macdev::Homebrew).to receive(:uninstall_package).with('rust')
        expect(Macdev::Homebrew).to receive(:uninstall_package).with('python')

        described_class.gc(true)
      end

      it 'removes all pure packages from global manifest' do
        described_class.gc(true)

        global = Macdev::Manifest.load(global_manifest_file)
        expect(global.packages).to be_empty
      end

      it 'removes gc packages from gc section' do
        described_class.gc(true)

        global = Macdev::Manifest.load(global_manifest_file)
        expect(global.gc).to be_empty
      end

      it 'calls cleanup and Lock.generate' do
        expect(Macdev::Homebrew).to receive(:cleanup)
        expect(Macdev::Lock).to receive(:generate)

        described_class.gc(true)
      end
    end

    context 'when gc(all: true) with no gc packages' do
      before do
        global = Macdev::Manifest.new(packages: { 'rust' => '*' })
        global.save(global_manifest_file)
      end

      it 'still uninstalls all pure packages' do
        expect(Macdev::Homebrew).to receive(:uninstall_package).with('rust')

        described_class.gc(true)
      end
    end

    context 'when gc(all: true) with no packages at all' do
      before do
        global = Macdev::Manifest.new
        global.save(global_manifest_file)
      end

      it 'does not call cleanup or Lock.generate' do
        expect(Macdev::Homebrew).not_to receive(:cleanup)
        expect(Macdev::Lock).not_to receive(:generate)

        described_class.gc(true)
      end
    end
  end

  describe '.sync' do
    before do
      # Mock add method since sync calls it
      allow(described_class).to receive(:add)
    end

    context 'when syncing taps' do
      before do
        global = Macdev::Manifest.new(taps: { 'homebrew/cask' => true, 'homebrew/core' => true })
        global.save(global_manifest_file)

        # Mock one tap already tapped, one not
        allow(Macdev::Homebrew).to receive(:tap_tapped?).with('homebrew/cask').and_return(true)
        allow(Macdev::Homebrew).to receive(:tap_tapped?).with('homebrew/core').and_return(false)
        allow(Macdev::Homebrew).to receive(:tap)
      end

      it 'taps missing taps' do
        expect(Macdev::Homebrew).to receive(:tap).with('homebrew/core')
        expect(Macdev::Homebrew).not_to receive(:tap).with('homebrew/cask')

        described_class.sync
      end
    end

    context 'when syncing pure packages' do
      before do
        # Local manifest has packages
        local = Macdev::Manifest.new(packages: { 'rust' => '*', 'python' => '3.11' })
        local.save(manifest_file)

        # Global manifest has rust but not python
        global = Macdev::Manifest.new(packages: { 'rust' => '*' })
        global.save(global_manifest_file)
      end

      it 'adds missing pure packages' do
        expect(described_class).to receive(:add).with('python@3.11', impure: false, cask: false)
        expect(described_class).not_to receive(:add).with('rust', any_args)

        described_class.sync
      end

      it 'uses unversioned spec when version is *' do
        local = Macdev::Manifest.new(packages: { 'node' => '*' })
        local.save(manifest_file)

        global = Macdev::Manifest.new
        global.save(global_manifest_file)

        expect(described_class).to receive(:add).with('node', impure: false, cask: false)

        described_class.sync
      end
    end

    context 'when syncing impure packages' do
      before do
        # Create local manifest (required for sync to run)
        local = Macdev::Manifest.new
        local.save(manifest_file)

        # Global manifest has impure packages
        global = Macdev::Manifest.new(impure: { 'git' => true, 'wget' => true })
        global.save(global_manifest_file)

        # Mock one installed, one not
        allow(Macdev::Homebrew).to receive(:package_installed?).with('git').and_return(true)
        allow(Macdev::Homebrew).to receive(:package_installed?).with('wget').and_return(false)
      end

      it 'adds missing impure packages' do
        expect(described_class).to receive(:add).with('wget', impure: true, cask: false)
        expect(described_class).not_to receive(:add).with('git', any_args)

        described_class.sync
      end
    end

    context 'when all items already synced' do
      before do
        # Local and global manifests match
        local = Macdev::Manifest.new(packages: { 'rust' => '*' })
        local.save(manifest_file)

        global = Macdev::Manifest.new(packages: { 'rust' => '*' })
        global.save(global_manifest_file)
      end

      it 'does not call add' do
        expect(described_class).not_to receive(:add)

        described_class.sync
      end
    end

    context 'when syncing all types together' do
      before do
        local = Macdev::Manifest.new(packages: { 'rust' => '*' })
        local.save(manifest_file)

        global = Macdev::Manifest.new(
          taps: { 'homebrew/cask' => true },
          impure: { 'git' => true }
        )
        global.save(global_manifest_file)

        allow(Macdev::Homebrew).to receive(:tap_tapped?).and_return(false)
        allow(Macdev::Homebrew).to receive(:tap)
        allow(Macdev::Homebrew).to receive(:package_installed?).and_return(false)
      end

      it 'syncs taps, pure packages, and impure packages' do
        expect(Macdev::Homebrew).to receive(:tap).with('homebrew/cask')
        expect(described_class).to receive(:add).with('rust', impure: false, cask: false)
        expect(described_class).to receive(:add).with('git', impure: true, cask: false)

        described_class.sync
      end
    end

    context 'when local manifest does not exist' do
      before do
        FileUtils.rm_f(manifest_file)

        global = Macdev::Manifest.new(impure: { 'git' => true })
        global.save(global_manifest_file)

        allow(Macdev::Homebrew).to receive(:package_installed?).and_return(false)
      end

      it 'still syncs global items' do
        expect(described_class).to receive(:add).with('git', impure: true, cask: false)

        described_class.sync
      end
    end
  end

  describe '.check' do
    around do |example|
      # Change to tmpdir so profile directory checks work correctly
      Dir.chdir(tmpdir) { example.run }
    end

    context 'when manifest does not exist' do
      before do
        FileUtils.rm_f(manifest_file)
      end

      it 'exits with error' do
        expect do
          described_class.check
        end.to raise_error(SystemExit)
      end

      it 'does not exit in quiet mode' do
        expect do
          described_class.check(true)
        end.to raise_error(SystemExit)
      end
    end

    context 'when packages are missing from global manifest' do
      before do
        # Local has packages but global doesn't
        local = Macdev::Manifest.new(packages: { 'rust' => '*' })
        local.save(manifest_file)

        global = Macdev::Manifest.new
        global.save(global_manifest_file)
      end

      it 'exits with error' do
        expect do
          described_class.check
        end.to raise_error(SystemExit)
      end
    end

    context 'when profile directory is missing' do
      before do
        # Create matching manifests
        local = Macdev::Manifest.new(packages: { 'rust' => '*' })
        local.save(manifest_file)

        global = Macdev::Manifest.new(packages: { 'rust' => '*' })
        global.save(global_manifest_file)

        # Ensure profile directory doesn't exist
        FileUtils.rm_rf('.macdev/profile')
      end

      it 'exits with error' do
        expect do
          described_class.check
        end.to raise_error(SystemExit)
      end
    end

    context 'when profile directory is empty' do
      before do
        # Create matching manifests
        local = Macdev::Manifest.new(packages: { 'rust' => '*' })
        local.save(manifest_file)

        global = Macdev::Manifest.new(packages: { 'rust' => '*' })
        global.save(global_manifest_file)

        # Create empty profile directory
        FileUtils.mkdir_p('.macdev/profile/bin')
      end

      it 'exits with error' do
        expect do
          described_class.check
        end.to raise_error(SystemExit)
      end
    end

    context 'when lock file is missing' do
      before do
        # Create matching manifests
        local = Macdev::Manifest.new(packages: { 'rust' => '*' })
        local.save(manifest_file)

        global = Macdev::Manifest.new(packages: { 'rust' => '*' })
        global.save(global_manifest_file)

        # Create non-empty profile directory
        FileUtils.mkdir_p('.macdev/profile/bin')
        FileUtils.touch('.macdev/profile/bin/rust')

        # Ensure lock file doesn't exist
        allow(Macdev::Lock).to receive(:exists?).and_return(false)
      end

      it 'generates lock file' do
        expect(Macdev::Lock).to receive(:generate)

        described_class.check
      end
    end

    context 'when all checks pass' do
      before do
        # Create matching manifests
        local = Macdev::Manifest.new(packages: { 'rust' => '*' })
        local.save(manifest_file)

        global = Macdev::Manifest.new(packages: { 'rust' => '*' })
        global.save(global_manifest_file)

        # Create non-empty profile directory
        FileUtils.mkdir_p('.macdev/profile/bin')
        FileUtils.touch('.macdev/profile/bin/rust')

        # Mock lock file exists
        allow(Macdev::Lock).to receive(:exists?).and_return(true)
      end

      it 'does not exit' do
        expect do
          described_class.check
        end.not_to raise_error
      end

      it 'does not generate lock if it exists' do
        expect(Macdev::Lock).not_to receive(:generate)

        described_class.check
      end

      it 'prints success message' do
        expect do
          described_class.check
        end.to output(/Environment is set up/).to_stdout
      end

      it 'does not print success in quiet mode' do
        expect do
          described_class.check(true)
        end.not_to output(/Environment is set up/).to_stdout
      end
    end

    context 'when local manifest is empty' do
      before do
        # Create empty local manifest
        local = Macdev::Manifest.new
        local.save(manifest_file)

        global = Macdev::Manifest.new
        global.save(global_manifest_file)

        # Create empty profile directory (ok for empty manifest)
        FileUtils.mkdir_p('.macdev/profile/bin')

        allow(Macdev::Lock).to receive(:exists?).and_return(true)
      end

      it 'exits because profile directory is empty' do
        expect do
          described_class.check
        end.to raise_error(SystemExit)
      end
    end
  end

  describe '.upgrade' do
    before do
      # Mock rebuild_profile to avoid filesystem operations
      allow(described_class).to receive(:rebuild_profile)

      # Mock Lock.generate
      allow(Macdev::Lock).to receive(:generate)
    end

    context 'when upgrading a specific pure package' do
      before do
        local = Macdev::Manifest.new(packages: { 'rust' => '*' })
        local.save(manifest_file)

        global = Macdev::Manifest.new(packages: { 'rust' => '*' })
        global.save(global_manifest_file)

        # Mock successful brew upgrade
        allow(described_class).to receive(:system).with('brew', 'upgrade', 'rust').and_return(true)
      end

      it 'runs brew upgrade for the package' do
        expect(described_class).to receive(:system).with('brew', 'upgrade', 'rust')

        described_class.upgrade('rust')
      end

      it 'rebuilds profile after upgrade' do
        expect(described_class).to receive(:rebuild_profile)

        described_class.upgrade('rust')
      end

      it 'generates lock file' do
        expect(Macdev::Lock).to receive(:generate)

        described_class.upgrade('rust')
      end
    end

    context 'when upgrading a specific impure package' do
      before do
        local = Macdev::Manifest.new
        local.save(manifest_file)

        global = Macdev::Manifest.new(impure: { 'git' => true })
        global.save(global_manifest_file)

        allow(described_class).to receive(:system).with('brew', 'upgrade', 'git').and_return(true)
      end

      it 'runs brew upgrade for the package' do
        expect(described_class).to receive(:system).with('brew', 'upgrade', 'git')

        described_class.upgrade('git')
      end

      it 'does not rebuild profile for impure packages' do
        expect(described_class).not_to receive(:rebuild_profile)

        described_class.upgrade('git')
      end
    end

    context 'when upgrading a package not managed by macdev' do
      before do
        local = Macdev::Manifest.new
        local.save(manifest_file)

        global = Macdev::Manifest.new
        global.save(global_manifest_file)
      end

      it 'aborts with error message' do
        expect do
          described_class.upgrade('nonexistent')
        end.to raise_error(SystemExit)
      end
    end

    context 'when brew upgrade fails' do
      before do
        local = Macdev::Manifest.new(packages: { 'rust' => '*' })
        local.save(manifest_file)

        global = Macdev::Manifest.new(packages: { 'rust' => '*' })
        global.save(global_manifest_file)

        # Mock failed brew upgrade
        allow(described_class).to receive(:system).with('brew', 'upgrade', 'rust').and_return(false)
      end

      it 'aborts with error message' do
        expect do
          described_class.upgrade('rust')
        end.to raise_error(SystemExit)
      end
    end

    context 'when upgrading all packages' do
      before do
        local = Macdev::Manifest.new(packages: { 'rust' => '*', 'node' => '20' })
        local.save(manifest_file)

        global = Macdev::Manifest.new(
          packages: { 'rust' => '*', 'node' => '20' },
          impure: { 'git' => true }
        )
        global.save(global_manifest_file)

        # Mock brew upgrade commands via backticks
        allow(described_class).to receive(:`).and_return('Upgrading rust')
        allow($?).to receive(:exitstatus).and_return(0)
      end

      it 'upgrades all pure packages' do
        expect(described_class).to receive(:`).with('brew upgrade rust 2>&1')
        expect(described_class).to receive(:`).with('brew upgrade node@20 2>&1')

        described_class.upgrade
      end

      it 'upgrades all impure packages' do
        expect(described_class).to receive(:`).with('brew upgrade git 2>&1')

        described_class.upgrade
      end

      it 'rebuilds profile after upgrading' do
        expect(described_class).to receive(:rebuild_profile)

        described_class.upgrade
      end

      it 'generates lock file' do
        expect(Macdev::Lock).to receive(:generate)

        described_class.upgrade
      end
    end

    context 'when upgrading python package' do
      before do
        local = Macdev::Manifest.new(packages: { 'python' => '3.11' })
        local.save(manifest_file)

        global = Macdev::Manifest.new(packages: { 'python' => '3.11' })
        global.save(global_manifest_file)
      end

      it 'shows venv recreation message for specific package upgrade' do
        allow(described_class).to receive(:system).with('brew', 'upgrade', 'python@3.11').and_return(true)

        expect do
          described_class.upgrade('python@3.11')
        end.to output(/You may want to recreate the venv/).to_stdout
      end

      it 'shows venv recreation message for upgrade all' do
        allow(described_class).to receive(:`).and_return('Upgrading python')
        allow($?).to receive(:exitstatus).and_return(0)

        expect do
          described_class.upgrade
        end.to output(/You may want to recreate the venv/).to_stdout
      end
    end

    context 'when packages are already up to date' do
      before do
        local = Macdev::Manifest.new(packages: { 'rust' => '*' })
        local.save(manifest_file)

        global = Macdev::Manifest.new(packages: { 'rust' => '*' })
        global.save(global_manifest_file)

        # Mock brew output indicating already installed
        allow(described_class).to receive(:`).and_return('rust 1.75.0 is already installed')
        allow($?).to receive(:exitstatus).and_return(0)
      end

      it 'still rebuilds profile' do
        expect(described_class).to receive(:rebuild_profile)

        described_class.upgrade
      end

      it 'still generates lock file' do
        expect(Macdev::Lock).to receive(:generate)

        described_class.upgrade
      end
    end

    context 'when local manifest is empty' do
      before do
        local = Macdev::Manifest.new
        local.save(manifest_file)

        global = Macdev::Manifest.new(impure: { 'git' => true })
        global.save(global_manifest_file)

        allow(described_class).to receive(:`).and_return('Upgrading git')
        allow($?).to receive(:exitstatus).and_return(0)
      end

      it 'only upgrades impure packages' do
        expect(described_class).to receive(:`).with('brew upgrade git 2>&1')

        described_class.upgrade
      end

      it 'does not rebuild profile' do
        expect(described_class).not_to receive(:rebuild_profile)

        described_class.upgrade
      end
    end
  end

  describe '.create_symlinks' do
    around do |example|
      # Change to tmpdir for profile directory operations
      Dir.chdir(tmpdir) { example.run }
    end

    let(:brew_prefix) { File.join(tmpdir, 'homebrew/opt/rust') }
    let(:profile_bin) { '.macdev/profile/bin' }

    context 'when package has binaries in bin/' do
      before do
        # Create fake homebrew prefix with bin directory
        FileUtils.mkdir_p(File.join(brew_prefix, 'bin'))
        FileUtils.touch(File.join(brew_prefix, 'bin', 'rustc'))
        FileUtils.touch(File.join(brew_prefix, 'bin', 'cargo'))
      end

      it 'creates symlinks in profile/bin' do
        described_class.create_symlinks('rust', brew_prefix)

        expect(File.symlink?(File.join(profile_bin, 'rustc'))).to be true
        expect(File.symlink?(File.join(profile_bin, 'cargo'))).to be true
      end

      it 'creates profile/bin directory if it does not exist' do
        expect(Dir.exist?(profile_bin)).to be false

        described_class.create_symlinks('rust', brew_prefix)

        expect(Dir.exist?(profile_bin)).to be true
      end

      it 'symlinks point to correct source files' do
        described_class.create_symlinks('rust', brew_prefix)

        rustc_link = File.readlink(File.join(profile_bin, 'rustc'))
        expect(rustc_link).to eq(File.join(brew_prefix, 'bin', 'rustc'))
      end
    end

    context 'when package has binaries in libexec/bin/' do
      before do
        # Create fake homebrew prefix with libexec/bin directory
        FileUtils.mkdir_p(File.join(brew_prefix, 'libexec/bin'))
        FileUtils.touch(File.join(brew_prefix, 'libexec/bin', 'python3'))
        FileUtils.touch(File.join(brew_prefix, 'libexec/bin', 'pip3'))
      end

      it 'creates symlinks for libexec binaries' do
        described_class.create_symlinks('python', brew_prefix)

        expect(File.symlink?(File.join(profile_bin, 'python3'))).to be true
        expect(File.symlink?(File.join(profile_bin, 'pip3'))).to be true
      end
    end

    context 'when package has binaries in both bin/ and libexec/bin/' do
      before do
        FileUtils.mkdir_p(File.join(brew_prefix, 'bin'))
        FileUtils.mkdir_p(File.join(brew_prefix, 'libexec/bin'))
        FileUtils.touch(File.join(brew_prefix, 'bin', 'main'))
        FileUtils.touch(File.join(brew_prefix, 'libexec/bin', 'helper'))
      end

      it 'creates symlinks from both directories' do
        described_class.create_symlinks('package', brew_prefix)

        expect(File.symlink?(File.join(profile_bin, 'main'))).to be true
        expect(File.symlink?(File.join(profile_bin, 'helper'))).to be true
      end
    end

    context 'when symlink already exists' do
      before do
        FileUtils.mkdir_p(File.join(brew_prefix, 'bin'))
        FileUtils.touch(File.join(brew_prefix, 'bin', 'rustc'))

        # Create existing symlink to different location
        FileUtils.mkdir_p(profile_bin)
        other_file = File.join(tmpdir, 'other')
        FileUtils.touch(other_file)
        File.symlink(other_file, File.join(profile_bin, 'rustc'))
      end

      it 'replaces existing symlink' do
        old_target = File.readlink(File.join(profile_bin, 'rustc'))

        described_class.create_symlinks('rust', brew_prefix)

        new_target = File.readlink(File.join(profile_bin, 'rustc'))
        expect(new_target).not_to eq(old_target)
        expect(new_target).to eq(File.join(brew_prefix, 'bin', 'rustc'))
      end
    end

    context 'when package has no binaries' do
      before do
        # Create prefix but no bin directories
        FileUtils.mkdir_p(brew_prefix)
      end

      it 'does not create any symlinks' do
        described_class.create_symlinks('package', brew_prefix)

        # Profile bin should be created but empty
        expect(Dir.exist?(profile_bin)).to be true
        expect(Dir.glob(File.join(profile_bin, '*'))).to be_empty
      end
    end

    context 'when bin directory has subdirectories' do
      before do
        FileUtils.mkdir_p(File.join(brew_prefix, 'bin'))
        FileUtils.touch(File.join(brew_prefix, 'bin', 'executable'))
        FileUtils.mkdir_p(File.join(brew_prefix, 'bin', 'subdir'))
      end

      it 'only symlinks files, not directories' do
        described_class.create_symlinks('package', brew_prefix)

        expect(File.symlink?(File.join(profile_bin, 'executable'))).to be true
        expect(File.exist?(File.join(profile_bin, 'subdir'))).to be false
      end
    end

    context 'when bin directory contains symlinks' do
      before do
        FileUtils.mkdir_p(File.join(brew_prefix, 'bin'))

        # Create a file and a symlink to it
        real_file = File.join(brew_prefix, 'bin', 'real')
        FileUtils.touch(real_file)
        File.symlink(real_file, File.join(brew_prefix, 'bin', 'link'))
      end

      it 'creates symlinks for both files and symlinks' do
        described_class.create_symlinks('package', brew_prefix)

        expect(File.symlink?(File.join(profile_bin, 'real'))).to be true
        expect(File.symlink?(File.join(profile_bin, 'link'))).to be true
      end
    end
  end

  describe '.normalize_python_symlinks' do
    around do |example|
      # Change to tmpdir for symlink operations
      Dir.chdir(tmpdir) { example.run }
    end

    before do
      # Create profile bin directory
      FileUtils.mkdir_p('.macdev/profile/bin')
    end

    context 'when versioned python exists' do
      before do
        # Create fake python3.13 binary
        FileUtils.touch('.macdev/profile/bin/python3.13')
        FileUtils.chmod(0o755, '.macdev/profile/bin/python3.13')
      end

      it 'creates python3 symlink' do
        described_class.send(:normalize_python_symlinks)

        expect(File.symlink?('.macdev/profile/bin/python3')).to be true
        expect(File.readlink('.macdev/profile/bin/python3')).to eq('python3.13')
      end

      it 'creates python symlink' do
        described_class.send(:normalize_python_symlinks)

        expect(File.symlink?('.macdev/profile/bin/python')).to be true
        expect(File.readlink('.macdev/profile/bin/python')).to eq('python3.13')
      end

      it 'outputs found message' do
        expect do
          described_class.send(:normalize_python_symlinks)
        end.to output(/Found Python binary: python3\.13/).to_stdout
      end

      it 'outputs success message' do
        expect do
          described_class.send(:normalize_python_symlinks)
        end.to output(/Normalized python and pip symlinks/).to_stdout
      end
    end

    context 'when versioned pip exists' do
      before do
        # Create fake python3.13 and pip3.13 binaries
        FileUtils.touch('.macdev/profile/bin/python3.13')
        FileUtils.touch('.macdev/profile/bin/pip3.13')
        FileUtils.chmod(0o755, '.macdev/profile/bin/python3.13')
        FileUtils.chmod(0o755, '.macdev/profile/bin/pip3.13')
      end

      it 'creates pip3 symlink' do
        described_class.send(:normalize_python_symlinks)

        expect(File.symlink?('.macdev/profile/bin/pip3')).to be true
        expect(File.readlink('.macdev/profile/bin/pip3')).to eq('pip3.13')
      end

      it 'creates pip symlink' do
        described_class.send(:normalize_python_symlinks)

        expect(File.symlink?('.macdev/profile/bin/pip')).to be true
        expect(File.readlink('.macdev/profile/bin/pip')).to eq('pip3.13')
      end
    end

    context 'when existing symlinks need to be replaced' do
      before do
        # Create new versioned python
        FileUtils.touch('.macdev/profile/bin/python3.13')

        # Create old symlinks pointing to different version
        File.symlink('python3.12', '.macdev/profile/bin/python3')
        File.symlink('python3.12', '.macdev/profile/bin/python')
      end

      it 'replaces python3 symlink' do
        described_class.send(:normalize_python_symlinks)

        expect(File.readlink('.macdev/profile/bin/python3')).to eq('python3.13')
      end

      it 'replaces python symlink' do
        described_class.send(:normalize_python_symlinks)

        expect(File.readlink('.macdev/profile/bin/python')).to eq('python3.13')
      end
    end

    context 'when python-config files exist' do
      before do
        # Create python binary and config files
        FileUtils.touch('.macdev/profile/bin/python3.13')
        FileUtils.touch('.macdev/profile/bin/python3.13-config')
      end

      it 'ignores config files when finding python binary' do
        described_class.send(:normalize_python_symlinks)

        expect(File.symlink?('.macdev/profile/bin/python3')).to be true
        expect(File.readlink('.macdev/profile/bin/python3')).to eq('python3.13')
      end
    end

    context 'when no versioned python exists' do
      it 'outputs warning' do
        expect do
          described_class.send(:normalize_python_symlinks)
        end.to output(/Could not find versioned Python binary/).to_stderr
      end

      it 'does not create symlinks' do
        described_class.send(:normalize_python_symlinks)

        expect(File.exist?('.macdev/profile/bin/python3')).to be false
        expect(File.exist?('.macdev/profile/bin/python')).to be false
      end
    end

    context 'when profile bin directory does not exist' do
      before do
        FileUtils.rm_rf('.macdev/profile/bin')
      end

      it 'outputs warning' do
        expect do
          described_class.send(:normalize_python_symlinks)
        end.to output(/Profile bin directory does not exist/).to_stderr
      end
    end

    context 'with different python versions' do
      it 'works with python3.11' do
        FileUtils.touch('.macdev/profile/bin/python3.11')
        FileUtils.touch('.macdev/profile/bin/pip3.11')

        described_class.send(:normalize_python_symlinks)

        expect(File.readlink('.macdev/profile/bin/python3')).to eq('python3.11')
        expect(File.readlink('.macdev/profile/bin/pip3')).to eq('pip3.11')
      end

      it 'works with python3.12' do
        FileUtils.touch('.macdev/profile/bin/python3.12')
        FileUtils.touch('.macdev/profile/bin/pip3.12')

        described_class.send(:normalize_python_symlinks)

        expect(File.readlink('.macdev/profile/bin/python3')).to eq('python3.12')
        expect(File.readlink('.macdev/profile/bin/pip3')).to eq('pip3.12')
      end
    end

    context 'when pip does not exist' do
      before do
        FileUtils.touch('.macdev/profile/bin/python3.13')
      end

      it 'still creates python symlinks' do
        described_class.send(:normalize_python_symlinks)

        expect(File.symlink?('.macdev/profile/bin/python3')).to be true
        expect(File.symlink?('.macdev/profile/bin/python')).to be true
      end

      it 'does not create pip symlinks' do
        described_class.send(:normalize_python_symlinks)

        expect(File.exist?('.macdev/profile/bin/pip3')).to be false
        expect(File.exist?('.macdev/profile/bin/pip')).to be false
      end
    end
  end

  describe '.setup_python_venv' do
    around do |example|
      # Change to tmpdir for venv operations
      Dir.chdir(tmpdir) { example.run }
    end

    before do
      # Create fake python binary in profile
      FileUtils.mkdir_p('.macdev/profile/bin')
      FileUtils.touch('.macdev/profile/bin/python3')
      FileUtils.chmod(0o755, '.macdev/profile/bin/python3')

      # Mock system call for venv creation
      allow(described_class).to receive(:system).and_return(true)
    end

    context 'when venv does not exist' do
      it 'creates a new venv' do
        expect(described_class).to receive(:system).with('.macdev/profile/bin/python3', '-m', 'venv', '.macdev/venv')

        described_class.send(:setup_python_venv)
      end

      it 'outputs creation message' do
        expect do
          described_class.send(:setup_python_venv)
        end.to output(/Creating Python virtual environment/).to_stdout
      end

      it 'outputs success message' do
        expect do
          described_class.send(:setup_python_venv)
        end.to output(/Python venv created/).to_stdout
      end
    end

    context 'when venv already exists' do
      before do
        FileUtils.mkdir_p('.macdev/venv')
      end

      it 'does not create venv' do
        expect(described_class).not_to receive(:system)

        described_class.send(:setup_python_venv)
      end

      it 'outputs already exists message' do
        expect do
          described_class.send(:setup_python_venv)
        end.to output(/venv already exists/).to_stdout
      end
    end

    context 'when python binary is missing' do
      before do
        FileUtils.rm_f('.macdev/profile/bin/python3')
      end

      it 'does not create venv' do
        expect(described_class).not_to receive(:system)

        described_class.send(:setup_python_venv)
      end

      it 'outputs warning' do
        expect do
          described_class.send(:setup_python_venv)
        end.to output(/Python binary not found/).to_stderr
      end
    end

    context 'when venv creation fails' do
      before do
        allow(described_class).to receive(:system).and_return(false)
      end

      it 'outputs failure warning' do
        expect do
          described_class.send(:setup_python_venv)
        end.to output(/Failed to create Python virtual environment/).to_stderr
      end
    end
  end

  describe 'Python venv integration' do
    around do |example|
      Dir.chdir(tmpdir) { example.run }
    end

    before do
      # Mock setup_python_venv to track calls
      allow(described_class).to receive(:setup_python_venv)
    end

    context 'when adding python package' do
      before do
        local = Macdev::Manifest.new
        local.save(manifest_file)

        global = Macdev::Manifest.new
        global.save(global_manifest_file)
      end

      it 'calls setup_python_venv for python' do
        expect(described_class).to receive(:setup_python_venv)

        described_class.add('python', impure: false, cask: false)
      end

      it 'calls setup_python_venv for python@3.11' do
        expect(described_class).to receive(:setup_python_venv)

        described_class.add('python@3.11', impure: false, cask: false)
      end

      it 'does not call setup_python_venv for non-python packages' do
        expect(described_class).not_to receive(:setup_python_venv)

        described_class.add('rust', impure: false, cask: false)
      end
    end

    context 'when installing from manifest' do
      before do
        local = Macdev::Manifest.new(packages: { 'python' => '3.11' })
        local.save(manifest_file)

        global = Macdev::Manifest.new
        global.save(global_manifest_file)
      end

      it 'calls setup_python_venv when python is in manifest' do
        expect(described_class).to receive(:setup_python_venv)

        described_class.install
      end
    end

    context 'when installing manifest without python' do
      before do
        local = Macdev::Manifest.new(packages: { 'rust' => '*' })
        local.save(manifest_file)

        global = Macdev::Manifest.new
        global.save(global_manifest_file)
      end

      it 'does not call setup_python_venv' do
        expect(described_class).not_to receive(:setup_python_venv)

        described_class.install
      end
    end
  end

  describe '.parse_package_spec' do
    it 'parses versioned package spec' do
      name, version = described_class.parse_package_spec('python@3.11')

      expect(name).to eq('python@3.11')
      expect(version).to eq('3.11')
    end

    it 'parses unversioned package spec' do
      name, version = described_class.parse_package_spec('rust')

      expect(name).to eq('rust')
      expect(version).to be_nil
    end

    it 'handles @ in package name' do
      name, version = described_class.parse_package_spec('node@20')

      expect(name).to eq('node@20')
      expect(version).to eq('20')
    end
  end
end
