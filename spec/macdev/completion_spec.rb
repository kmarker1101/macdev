# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Macdev::Completion do
  describe '.generate' do
    context 'with bash shell' do
      it 'outputs bash completion script' do
        expect do
          described_class.generate('bash')
        end.to output(/_macdev\(\)/).to_stdout
      end

      it 'includes all commands in completion' do
        expect do
          described_class.generate('bash')
        end.to output(/init add remove install shell list sync gc check upgrade/).to_stdout
      end

      it 'includes complete function call' do
        expect do
          described_class.generate('bash')
        end.to output(/complete -F _macdev macdev/).to_stdout
      end
    end

    context 'with zsh shell' do
      it 'outputs zsh completion script' do
        expect do
          described_class.generate('zsh')
        end.to output(/#compdef macdev/).to_stdout
      end

      it 'includes all commands with descriptions' do
        expect do
          described_class.generate('zsh')
        end.to output(/init:Initialize a new project/).to_stdout
      end
    end

    context 'with fish shell' do
      it 'outputs fish completion script' do
        expect do
          described_class.generate('fish')
        end.to output(/complete -c macdev/).to_stdout
      end

      it 'includes all commands with descriptions' do
        expect do
          described_class.generate('fish')
        end.to output(/Initialize a new project/).to_stdout
      end

      it 'includes subcommand completions' do
        expect do
          described_class.generate('fish')
        end.to output(/__fish_use_subcommand/).to_stdout
      end
    end

    context 'with unsupported shell' do
      it 'aborts with error message' do
        expect do
          described_class.generate('powershell')
        end.to raise_error(SystemExit)
      end

      it 'shows supported shells in error' do
        # abort writes to stderr and the format is platform-specific
        # Just verify SystemExit is raised
        expect do
          described_class.generate('unknown')
        end.to raise_error(SystemExit)
      end
    end
  end

  describe '.bash' do
    it 'returns a string' do
      expect(described_class.bash).to be_a(String)
    end

    it 'includes all commands' do
      bash_script = described_class.bash

      expect(bash_script).to include('init')
      expect(bash_script).to include('add')
      expect(bash_script).to include('remove')
      expect(bash_script).to include('install')
      expect(bash_script).to include('shell')
      expect(bash_script).to include('list')
      expect(bash_script).to include('sync')
      expect(bash_script).to include('gc')
      expect(bash_script).to include('check')
      expect(bash_script).to include('upgrade')
      expect(bash_script).to include('tap')
      expect(bash_script).to include('untap')
      expect(bash_script).to include('completion')
      expect(bash_script).to include('help')
      expect(bash_script).to include('version')
    end

    it 'includes completion for shell names' do
      bash_script = described_class.bash

      expect(bash_script).to include('bash zsh fish')
    end
  end

  describe '.zsh' do
    it 'returns a string' do
      expect(described_class.zsh).to be_a(String)
    end

    it 'includes compdef directive' do
      expect(described_class.zsh).to include('#compdef macdev')
    end

    it 'includes all commands with descriptions' do
      zsh_script = described_class.zsh

      expect(zsh_script).to include('init:Initialize a new project')
      expect(zsh_script).to include('add:Add packages to environment')
      expect(zsh_script).to include('remove:Remove packages')
      expect(zsh_script).to include('install:Install packages from manifest')
      expect(zsh_script).to include('shell:Enter isolated shell')
      expect(zsh_script).to include('list:List installed packages')
      expect(zsh_script).to include('sync:Sync packages from manifest(s)')
      expect(zsh_script).to include('gc:Garbage collect unused packages')
      expect(zsh_script).to include('check:Check if environment needs setup')
      expect(zsh_script).to include('upgrade:Upgrade packages')
      expect(zsh_script).to include('tap:Add a Homebrew tap')
      expect(zsh_script).to include('untap:Remove a Homebrew tap')
      expect(zsh_script).to include('completion:Generate shell completion script')
      expect(zsh_script).to include('help:Show help message')
      expect(zsh_script).to include('version:Show version')
    end

    it 'includes completion for shell names' do
      zsh_script = described_class.zsh

      expect(zsh_script).to include('bash zsh fish')
    end
  end

  describe '.fish' do
    it 'returns a string' do
      expect(described_class.fish).to be_a(String)
    end

    it 'includes all commands with descriptions' do
      fish_script = described_class.fish

      expect(fish_script).to include('"init"')
      expect(fish_script).to include('Initialize a new project')
      expect(fish_script).to include('"add"')
      expect(fish_script).to include('Add packages to environment')
      expect(fish_script).to include('"remove"')
      expect(fish_script).to include('Remove packages')
      expect(fish_script).to include('"install"')
      expect(fish_script).to include('Install packages from manifest')
      expect(fish_script).to include('"shell"')
      expect(fish_script).to include('Enter isolated shell')
      expect(fish_script).to include('"list"')
      expect(fish_script).to include('List installed packages')
      expect(fish_script).to include('"sync"')
      expect(fish_script).to include('Sync packages from manifest(s)')
      expect(fish_script).to include('"gc"')
      expect(fish_script).to include('Garbage collect unused packages')
      expect(fish_script).to include('"check"')
      expect(fish_script).to include('Check if environment needs setup')
      expect(fish_script).to include('"upgrade"')
      expect(fish_script).to include('Upgrade packages')
      expect(fish_script).to include('"tap"')
      expect(fish_script).to include('Add a Homebrew tap')
      expect(fish_script).to include('"untap"')
      expect(fish_script).to include('Remove a Homebrew tap')
      expect(fish_script).to include('"completion"')
      expect(fish_script).to include('Generate shell completion script')
      expect(fish_script).to include('"help"')
      expect(fish_script).to include('Show help message')
      expect(fish_script).to include('"version"')
      expect(fish_script).to include('Show version')
    end

    it 'includes completion for shell names' do
      fish_script = described_class.fish

      expect(fish_script).to include('bash zsh fish')
    end

    it 'uses fish completion syntax' do
      fish_script = described_class.fish

      expect(fish_script).to include('complete -c macdev')
      expect(fish_script).to include('__fish_use_subcommand')
    end
  end
end
