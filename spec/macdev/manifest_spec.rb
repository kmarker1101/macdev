# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Macdev::Manifest do
  let(:tmpdir) { Dir.mktmpdir }
  let(:manifest_file) { File.join(tmpdir, 'macdev.toml') }
  let(:global_manifest_file) { File.join(tmpdir, '.config/macdev/macdev.toml') }

  before do
    # Stub constants to use tmpdir instead of real paths
    stub_const('Macdev::Manifest::MANIFEST_FILE', manifest_file)
    stub_const('Macdev::Manifest::GLOBAL_MANIFEST', global_manifest_file)
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe '.new' do
    it 'creates an empty manifest' do
      manifest = described_class.new

      expect(manifest.packages).to eq({})
      expect(manifest.impure).to eq({})
      expect(manifest.casks).to eq({})
      expect(manifest.gc).to eq({})
      expect(manifest.taps).to eq({})
    end

    it 'accepts initial values' do
      manifest = described_class.new(
        packages: { 'rust' => '*' },
        impure: { 'git' => true },
        casks: { 'firefox' => true },
        garbage_collect: { 'old-pkg' => '*' },
        taps: { 'homebrew/cask' => true }
      )

      expect(manifest.packages).to eq({ 'rust' => '*' })
      expect(manifest.impure).to eq({ 'git' => true })
      expect(manifest.casks).to eq({ 'firefox' => true })
      expect(manifest.gc).to eq({ 'old-pkg' => '*' })
      expect(manifest.taps).to eq({ 'homebrew/cask' => true })
    end
  end

  describe '#add_package' do
    it 'adds a package' do
      manifest = described_class.new
      manifest.add_package('python', '3.11')

      expect(manifest.packages).to eq({ 'python' => '3.11' })
    end
  end

  describe '#remove_package' do
    it 'removes a package' do
      manifest = described_class.new(packages: { 'python' => '3.11', 'rust' => '*' })
      manifest.remove_package('python')

      expect(manifest.packages).to eq({ 'rust' => '*' })
    end
  end

  describe '#add_to_gc' do
    it 'adds a package to garbage collection' do
      manifest = described_class.new
      manifest.add_to_gc('old-package', '1.0')

      expect(manifest.gc).to eq({ 'old-package' => '1.0' })
    end
  end

  describe '#remove_from_gc' do
    it 'removes a package from garbage collection' do
      manifest = described_class.new(garbage_collect: { 'old-package' => '1.0' })
      manifest.remove_from_gc('old-package')

      expect(manifest.gc).to be_empty
    end
  end

  describe '#save' do
    it 'saves manifest to file' do
      FileUtils.mkdir_p(File.dirname(manifest_file))
      manifest = described_class.new(packages: { 'rust' => '*' })

      manifest.save(manifest_file)

      expect(File.exist?(manifest_file)).to be true
      content = File.read(manifest_file)
      expect(content).to include('[packages]')
      expect(content).to include('rust = "*"')
    end

    it 'only saves packages section for local manifest' do
      FileUtils.mkdir_p(File.dirname(manifest_file))
      manifest = described_class.new(
        packages: { 'rust' => '*' },
        impure: { 'git' => true }
      )

      manifest.save(manifest_file)

      content = File.read(manifest_file)
      expect(content).to include('rust')
      expect(content).not_to include('impure')
    end
  end

  describe '.load' do
    it 'loads manifest from file' do
      FileUtils.mkdir_p(File.dirname(manifest_file))
      File.write(manifest_file, <<~TOML)
        [packages]
        rust = "*"
        python = "3.11"
      TOML

      manifest = described_class.load(manifest_file)

      expect(manifest.packages).to eq({ 'rust' => '*', 'python' => '3.11' })
    end

    it 'returns nil if file does not exist' do
      manifest = described_class.load('/nonexistent/path')

      expect(manifest).to be_nil
    end

    it 'loads all sections from global manifest' do
      FileUtils.mkdir_p(File.dirname(global_manifest_file))
      File.write(global_manifest_file, <<~TOML)
        [packages]
        rust = "*"

        [impure]
        git = true

        [casks]
        firefox = true

        [gc]
        old-pkg = "*"

        [taps]
        "homebrew/cask" = true
      TOML

      manifest = described_class.load(global_manifest_file)

      expect(manifest.packages).to eq({ 'rust' => '*' })
      expect(manifest.impure).to eq({ 'git' => true })
      expect(manifest.casks).to eq({ 'firefox' => true })
      expect(manifest.gc).to eq({ 'old-pkg' => '*' })
      expect(manifest.taps).to eq({ 'homebrew/cask' => true })
    end
  end

  describe '.init' do
    it 'creates a new manifest file' do
      expect do
        described_class.init
      end.to output(/Initialized macdev environment/).to_stdout

      expect(File.exist?(manifest_file)).to be true
      content = File.read(manifest_file)
      expect(content).to include('[packages]')
    end

    it 'does not overwrite existing manifest' do
      FileUtils.mkdir_p(File.dirname(manifest_file))
      File.write(manifest_file, '[packages]')

      expect do
        described_class.init
      end.to output(/already exists/).to_stdout

      expect(File.exist?(manifest_file)).to be true
    end
  end
end
