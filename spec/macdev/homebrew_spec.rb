# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Macdev::Homebrew do
  describe '.installed?' do
    it 'returns true when brew is installed' do
      allow(described_class).to receive(:system).with('which brew > /dev/null 2>&1').and_return(true)

      expect(described_class.installed?).to be true
    end

    it 'returns false when brew is not installed' do
      allow(described_class).to receive(:system).with('which brew > /dev/null 2>&1').and_return(false)

      expect(described_class.installed?).to be false
    end
  end

  describe '.package_installed?' do
    it 'returns true when package is installed' do
      allow(described_class).to receive(:system).and_return(true)

      expect(described_class.package_installed?('rust')).to be true
    end

    it 'returns false when package is not installed' do
      allow(described_class).to receive(:system).and_return(false)

      expect(described_class.package_installed?('nonexistent')).to be false
    end
  end

  describe '.prefix' do
    it 'returns package prefix path' do
      allow(described_class).to receive(:`).and_return("/opt/homebrew/opt/rust\n")
      allow($?).to receive(:exitstatus).and_return(0)

      expect(described_class.prefix('rust')).to eq('/opt/homebrew/opt/rust')
    end

    it 'returns nil when package not found' do
      allow(described_class).to receive(:`).and_return('')
      allow($?).to receive(:exitstatus).and_return(1)

      expect(described_class.prefix('nonexistent')).to be_nil
    end

    it 'returns nil when output is empty' do
      allow(described_class).to receive(:`).and_return('')
      allow($?).to receive(:exitstatus).and_return(0)

      expect(described_class.prefix('package')).to be_nil
    end
  end

  describe '.package_info' do
    let(:brew_info_json) do
      {
        'formulae' => [
          {
            'full_name' => 'rust',
            'versions' => { 'stable' => '1.75.0' }
          }
        ]
      }.to_json
    end

    it 'returns package info' do
      allow(described_class).to receive(:`).and_return(brew_info_json)
      allow($?).to receive(:exitstatus).and_return(0)

      info = described_class.package_info('rust')

      expect(info[:version]).to eq('1.75.0')
      expect(info[:formula]).to eq('rust')
    end

    it 'returns nil when package not found' do
      allow(described_class).to receive(:`).and_return('')
      allow($?).to receive(:exitstatus).and_return(1)

      expect(described_class.package_info('nonexistent')).to be_nil
    end

    it 'returns nil when JSON is invalid' do
      allow(described_class).to receive(:`).and_return('invalid json')
      allow($?).to receive(:exitstatus).and_return(0)

      expect(described_class.package_info('package')).to be_nil
    end
  end

  describe '.package_deps' do
    it 'returns list of dependencies' do
      allow(described_class).to receive(:`).and_return("openssl\nzlib\n")
      allow($?).to receive(:exitstatus).and_return(0)

      deps = described_class.package_deps('rust')

      expect(deps).to eq(%w[openssl zlib])
    end

    it 'returns empty array when no dependencies' do
      allow(described_class).to receive(:`).and_return('')
      allow($?).to receive(:exitstatus).and_return(0)

      deps = described_class.package_deps('simple-package')

      expect(deps).to eq([])
    end

    it 'returns empty array when command fails' do
      allow(described_class).to receive(:`).and_return('')
      allow($?).to receive(:exitstatus).and_return(1)

      deps = described_class.package_deps('nonexistent')

      expect(deps).to eq([])
    end
  end

  describe '.tap_tapped?' do
    it 'returns true when tap is tapped' do
      allow(described_class).to receive(:system).and_return(true)

      expect(described_class.tap_tapped?('homebrew/cask')).to be true
    end

    it 'returns false when tap is not tapped' do
      allow(described_class).to receive(:system).and_return(false)

      expect(described_class.tap_tapped?('some/tap')).to be false
    end
  end
end
