# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Macdev::CLI do
  before do
    # Mock all commands to avoid side effects
    allow(Macdev::Manifest).to receive(:init)
    allow(Macdev::Manifest).to receive(:list)
    allow(Macdev::Environment).to receive(:add)
    allow(Macdev::Environment).to receive(:remove)
    allow(Macdev::Environment).to receive(:install)
    allow(Macdev::Environment).to receive(:gc)
    allow(Macdev::Environment).to receive(:sync)
    allow(Macdev::Environment).to receive(:check)
    allow(Macdev::Environment).to receive(:upgrade)
    allow(Macdev::Environment).to receive(:shell)
    allow(Macdev::Environment).to receive(:tap)
    allow(Macdev::Environment).to receive(:untap)
    allow(Macdev::Completion).to receive(:generate)
  end

  describe '.run' do
    context 'with init command' do
      it 'calls Manifest.init' do
        expect(Macdev::Manifest).to receive(:init)

        described_class.run(['init'])
      end
    end

    context 'with add command' do
      it 'calls Environment.add for each package' do
        expect(Macdev::Environment).to receive(:add).with('rust', impure: nil, cask: nil)
        expect(Macdev::Environment).to receive(:add).with('node', impure: nil, cask: nil)

        described_class.run(%w[add rust node])
      end

      it 'passes impure flag correctly' do
        expect(Macdev::Environment).to receive(:add).with('git', impure: '--impure', cask: nil)

        described_class.run(['add', '--impure', 'git'])
      end

      it 'passes cask flag correctly' do
        expect(Macdev::Environment).to receive(:add).with('firefox', impure: nil, cask: '--cask')

        described_class.run(['add', '--cask', 'firefox'])
      end

      it 'handles both flags together' do
        expect(Macdev::Environment).to receive(:add).with('app', impure: '--impure', cask: '--cask')

        described_class.run(['add', '--impure', '--cask', 'app'])
      end

      it 'aborts when no packages specified' do
        expect do
          described_class.run(['add'])
        end.to raise_error(SystemExit)
      end

      it 'aborts when only flags specified' do
        expect do
          described_class.run(['add', '--impure'])
        end.to raise_error(SystemExit)
      end
    end

    context 'with remove command' do
      it 'calls Environment.remove for each package' do
        expect(Macdev::Environment).to receive(:remove).with('rust')
        expect(Macdev::Environment).to receive(:remove).with('node')

        described_class.run(%w[remove rust node])
      end

      it 'aborts when no packages specified' do
        expect do
          described_class.run(['remove'])
        end.to raise_error(SystemExit)
      end
    end

    context 'with install command' do
      it 'calls Environment.install' do
        expect(Macdev::Environment).to receive(:install)

        described_class.run(['install'])
      end
    end

    context 'with gc command' do
      it 'calls Environment.gc without all flag' do
        expect(Macdev::Environment).to receive(:gc).with(nil)

        described_class.run(['gc'])
      end

      it 'calls Environment.gc with all flag' do
        expect(Macdev::Environment).to receive(:gc).with('--all')

        described_class.run(['gc', '--all'])
      end
    end

    context 'with sync command' do
      it 'calls Environment.sync' do
        expect(Macdev::Environment).to receive(:sync)

        described_class.run(['sync'])
      end
    end

    context 'with check command' do
      it 'calls Environment.check without quiet flag' do
        expect(Macdev::Environment).to receive(:check).with(nil)

        described_class.run(['check'])
      end

      it 'calls Environment.check with quiet flag' do
        expect(Macdev::Environment).to receive(:check).with('--quiet')

        described_class.run(['check', '--quiet'])
      end
    end

    context 'with upgrade command' do
      it 'calls Environment.upgrade with no package' do
        expect(Macdev::Environment).to receive(:upgrade).with(nil)

        described_class.run(['upgrade'])
      end

      it 'calls Environment.upgrade with specific package' do
        expect(Macdev::Environment).to receive(:upgrade).with('rust')

        described_class.run(%w[upgrade rust])
      end
    end

    context 'with list command' do
      it 'calls Manifest.list' do
        expect(Macdev::Manifest).to receive(:list)

        described_class.run(['list'])
      end
    end

    context 'with shell command' do
      it 'calls Environment.shell' do
        expect(Macdev::Environment).to receive(:shell)

        described_class.run(['shell'])
      end
    end

    context 'with tap command' do
      it 'calls Environment.tap with tap name' do
        expect(Macdev::Environment).to receive(:tap).with('homebrew/cask')

        described_class.run(['tap', 'homebrew/cask'])
      end

      it 'aborts when no tap specified' do
        expect do
          described_class.run(['tap'])
        end.to raise_error(SystemExit)
      end
    end

    context 'with untap command' do
      it 'calls Environment.untap with tap name' do
        expect(Macdev::Environment).to receive(:untap).with('homebrew/cask')

        described_class.run(['untap', 'homebrew/cask'])
      end

      it 'aborts when no tap specified' do
        expect do
          described_class.run(['untap'])
        end.to raise_error(SystemExit)
      end
    end

    context 'with completion command' do
      it 'calls Completion.generate with shell name' do
        expect(Macdev::Completion).to receive(:generate).with('bash')

        described_class.run(%w[completion bash])
      end

      it 'aborts when no shell specified' do
        expect do
          described_class.run(['completion'])
        end.to raise_error(SystemExit)
      end
    end

    context 'with version command' do
      it 'prints version for "version"' do
        expect do
          described_class.run(['version'])
        end.to output(/macdev #{Macdev::VERSION}/).to_stdout
      end

      it 'prints version for "--version"' do
        expect do
          described_class.run(['--version'])
        end.to output(/macdev #{Macdev::VERSION}/).to_stdout
      end

      it 'prints version for "-v"' do
        expect do
          described_class.run(['-v'])
        end.to output(/macdev #{Macdev::VERSION}/).to_stdout
      end
    end

    context 'with help command' do
      it 'shows help for "help"' do
        expect do
          described_class.run(['help'])
        end.to output(/USAGE:/).to_stdout
      end

      it 'shows help for "--help"' do
        expect do
          described_class.run(['--help'])
        end.to output(/USAGE:/).to_stdout
      end

      it 'shows help for "-h"' do
        expect do
          described_class.run(['-h'])
        end.to output(/USAGE:/).to_stdout
      end

      it 'shows help when no command given' do
        expect do
          described_class.run([])
        end.to output(/USAGE:/).to_stdout
      end
    end

    context 'with unknown command' do
      it 'prints error and shows help' do
        expect do
          described_class.run(['unknown'])
        end.to output(/Unknown command: unknown/).to_stdout.and raise_error(SystemExit)
      end
    end
  end

  describe '.show_help' do
    it 'prints help text' do
      expect do
        described_class.show_help
      end.to output(/USAGE:/).to_stdout
    end

    it 'includes all commands' do
      expect do
        described_class.show_help
      end.to output(/init.*add.*remove.*install.*shell/m).to_stdout
    end
  end
end
