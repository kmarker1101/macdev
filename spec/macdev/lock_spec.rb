# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'

RSpec.describe Macdev::Lock do
  let(:tmpdir) { Dir.mktmpdir }
  let(:lock_file) { File.join(tmpdir, 'macdev.lock') }
  let(:manifest_file) { File.join(tmpdir, 'macdev.toml') }

  before do
    # Stub file paths to use tmpdir
    stub_const('Macdev::Manifest::LOCK_FILE', lock_file)
    stub_const('Macdev::Manifest::MANIFEST_FILE', manifest_file)

    # Mock Homebrew calls
    allow(Macdev::Homebrew).to receive(:package_info).and_return(nil)
    allow(Macdev::Homebrew).to receive(:package_deps).and_return([])
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe '.new' do
    it 'creates a lock with metadata' do
      lock = described_class.new

      expect(lock.metadata).to include('macdev_version' => Macdev::VERSION)
      expect(lock.metadata['generated']).to match(/^\d{4}-\d{2}-\d{2}T/)
      expect(lock.packages).to eq({})
      expect(lock.dependencies).to eq({})
    end
  end

  describe '#add_package' do
    it 'adds a package with version and formula' do
      lock = described_class.new
      lock.add_package('rust', '1.75.0', 'rust')

      expect(lock.packages).to eq({
        'rust' => {
          'version' => '1.75.0',
          'formula' => 'rust'
        }
      })
    end

    it 'adds multiple packages' do
      lock = described_class.new
      lock.add_package('rust', '1.75.0', 'rust')
      lock.add_package('python', '3.11.7', 'python@3.11')

      expect(lock.packages.keys).to contain_exactly('rust', 'python')
    end
  end

  describe '#add_dependency' do
    it 'adds a dependency with package:dep key format' do
      lock = described_class.new
      lock.add_dependency('rust', 'openssl', '3.2.0', 'openssl@3')

      expect(lock.dependencies).to eq({
        'rust:openssl' => {
          'version' => '3.2.0',
          'formula' => 'openssl@3'
        }
      })
    end

    it 'adds multiple dependencies for same package' do
      lock = described_class.new
      lock.add_dependency('rust', 'openssl', '3.2.0', 'openssl@3')
      lock.add_dependency('rust', 'zlib', '1.3', 'zlib')

      expect(lock.dependencies.keys).to contain_exactly('rust:openssl', 'rust:zlib')
    end
  end

  describe '#save' do
    it 'saves lock file to disk' do
      lock = described_class.new
      lock.add_package('rust', '1.75.0', 'rust')

      lock.save

      expect(File.exist?(lock_file)).to be true
      content = File.read(lock_file)
      expect(content).to include('[metadata]')
      expect(content).to include('[packages.rust]')
      expect(content).to include('version = "1.75.0"')
    end

    it 'excludes empty sections except metadata' do
      lock = described_class.new
      # No packages or dependencies added

      lock.save

      content = File.read(lock_file)
      expect(content).to include('[metadata]')
      expect(content).not_to include('[packages]')
      expect(content).not_to include('[dependencies]')
    end
  end

  describe '.load' do
    it 'loads lock file from disk' do
      FileUtils.mkdir_p(File.dirname(lock_file))
      File.write(lock_file, <<~TOML)
        [metadata]
        generated = "2025-01-15T10:00:00Z"
        macdev_version = "0.1.0"

        [packages]
        [packages.rust]
        version = "1.75.0"
        formula = "rust"

        [dependencies]
        [dependencies."rust:openssl"]
        version = "3.2.0"
        formula = "openssl@3"
      TOML

      lock = described_class.load

      expect(lock).not_to be_nil
      expect(lock.metadata['macdev_version']).to eq('0.1.0')
      expect(lock.packages['rust']['version']).to eq('1.75.0')
      expect(lock.dependencies['rust:openssl']['version']).to eq('3.2.0')
    end

    it 'returns nil if file does not exist' do
      lock = described_class.load

      expect(lock).to be_nil
    end

    it 'returns nil if file is invalid TOML' do
      FileUtils.mkdir_p(File.dirname(lock_file))
      File.write(lock_file, 'invalid toml content [[[')

      expect do
        lock = described_class.load
        expect(lock).to be_nil
      end.to output(/Warning: Failed to load/).to_stderr
    end

    it 'handles missing sections gracefully' do
      FileUtils.mkdir_p(File.dirname(lock_file))
      File.write(lock_file, <<~TOML)
        [metadata]
        generated = "2025-01-15T10:00:00Z"
      TOML

      lock = described_class.load

      expect(lock.metadata['generated']).to eq('2025-01-15T10:00:00Z')
      expect(lock.packages).to eq({})
      expect(lock.dependencies).to eq({})
    end
  end

  describe '.exists?' do
    it 'returns true when lock file exists' do
      FileUtils.mkdir_p(File.dirname(lock_file))
      File.write(lock_file, '[metadata]')

      expect(described_class.exists?).to be true
    end

    it 'returns false when lock file does not exist' do
      expect(described_class.exists?).to be false
    end
  end

  describe '.generate' do
    let(:manifest) do
      Macdev::Manifest.new(packages: { 'rust' => '*', 'python' => '3.11' })
    end

    before do
      # Mock manifest loading
      allow(Macdev::Manifest).to receive(:load).and_return(manifest)

      # Mock Homebrew package info
      allow(Macdev::Homebrew).to receive(:package_info).with('rust').and_return(
        { version: '1.75.0', formula: 'rust' }
      )
      allow(Macdev::Homebrew).to receive(:package_info).with('python@3.11').and_return(
        { version: '3.11.7', formula: 'python@3.11' }
      )
      allow(Macdev::Homebrew).to receive(:package_info).with('openssl').and_return(
        { version: '3.2.0', formula: 'openssl@3' }
      )

      # Mock dependencies
      allow(Macdev::Homebrew).to receive(:package_deps).with('rust').and_return(['openssl'])
      allow(Macdev::Homebrew).to receive(:package_deps).with('python@3.11').and_return([])
    end

    it 'generates lock file from manifest' do
      expect do
        described_class.generate
      end.to output(/Generating lock file/).to_stdout

      expect(File.exist?(lock_file)).to be true
    end

    it 'locks all packages from manifest' do
      described_class.generate

      lock = described_class.load
      expect(lock.packages.keys).to contain_exactly('rust', 'python')
      expect(lock.packages['rust']['version']).to eq('1.75.0')
      expect(lock.packages['python']['version']).to eq('3.11.7')
    end

    it 'locks package dependencies' do
      described_class.generate

      lock = described_class.load
      expect(lock.dependencies).to have_key('rust:openssl')
      expect(lock.dependencies['rust:openssl']['version']).to eq('3.2.0')
    end

    it 'uses versioned package spec when version is not *' do
      expect(Macdev::Homebrew).to receive(:package_info).with('python@3.11')

      described_class.generate
    end

    it 'uses unversioned package spec when version is *' do
      expect(Macdev::Homebrew).to receive(:package_info).with('rust')

      described_class.generate
    end

    it 'deletes lock file when manifest has no packages' do
      empty_manifest = Macdev::Manifest.new(packages: {})
      allow(Macdev::Manifest).to receive(:load).and_return(empty_manifest)

      # Create a lock file first
      FileUtils.mkdir_p(File.dirname(lock_file))
      File.write(lock_file, '[metadata]')
      expect(File.exist?(lock_file)).to be true

      described_class.generate

      expect(File.exist?(lock_file)).to be false
    end

    it 'does nothing when manifest does not exist' do
      allow(Macdev::Manifest).to receive(:load).and_return(nil)

      described_class.generate

      expect(File.exist?(lock_file)).to be false
    end

    it 'skips packages that brew cannot find' do
      allow(Macdev::Homebrew).to receive(:package_info).with('rust').and_return(nil)

      described_class.generate

      lock = described_class.load
      expect(lock.packages).not_to have_key('rust')
      expect(lock.packages).to have_key('python')
    end
  end
end
