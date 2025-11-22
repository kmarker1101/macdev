# frozen_string_literal: true

module Macdev
  # Shell completion script generator
  class Completion
    def self.generate(shell_name)
      case shell_name
      when 'bash'
        puts bash
      when 'zsh'
        puts zsh
      when 'fish'
        puts fish
      else
        abort "\e[31mUnsupported shell: #{shell_name}\e[0m\nSupported shells: bash, zsh, fish"
      end
    end

    def self.bash
      <<~BASH
        _macdev() {
            local cur prev commands
            COMPREPLY=()
            cur="${COMP_WORDS[COMP_CWORD]}"
            prev="${COMP_WORDS[COMP_CWORD-1]}"
            commands="init add remove install shell list sync gc check upgrade tap untap completion help version"

            if [[ ${COMP_CWORD} == 1 ]]; then
                COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
                return 0
            fi

            case "${prev}" in
                completion)
                    COMPREPLY=( $(compgen -W "bash zsh fish" -- ${cur}) )
                    return 0
                    ;;
            esac
        }
        complete -F _macdev macdev
      BASH
    end

    def self.zsh
      <<~ZSH
        #compdef macdev

        _macdev() {
            local -a commands
            commands=(
                'init:Initialize a new project'
                'add:Add packages to environment'
                'remove:Remove packages'
                'install:Install packages from manifest'
                'shell:Enter isolated shell'
                'list:List installed packages'
                'sync:Sync packages from manifest(s)'
                'gc:Garbage collect unused packages'
                'check:Check if environment needs setup'
                'upgrade:Upgrade packages'
                'tap:Add a Homebrew tap'
                'untap:Remove a Homebrew tap'
                'completion:Generate shell completion script'
                'help:Show help message'
                'version:Show version'
            )

            if (( CURRENT == 2 )); then
                _describe 'command' commands
            elif (( CURRENT == 3 )); then
                case "$words[2]" in
                    completion)
                        _values 'shell' bash zsh fish
                       ;;
                esac
            fi
        }

        _macdev
      ZSH
    end

    def self.fish
      <<~FISH
        complete -c macdev -f
        complete -c macdev -n "__fish_use_subcommand" -a "init" -d "Initialize a new project"
        complete -c macdev -n "__fish_use_subcommand" -a "add" -d "Add packages to environment"
        complete -c macdev -n "__fish_use_subcommand" -a "remove" -d "Remove packages"
        complete -c macdev -n "__fish_use_subcommand" -a "install" -d "Install packages from manifest"
        complete -c macdev -n "__fish_use_subcommand" -a "shell" -d "Enter isolated shell"
        complete -c macdev -n "__fish_use_subcommand" -a "list" -d "List installed packages"
        complete -c macdev -n "__fish_use_subcommand" -a "sync" -d "Sync packages from manifest(s)"
        complete -c macdev -n "__fish_use_subcommand" -a "gc" -d "Garbage collect unused packages"
        complete -c macdev -n "__fish_use_subcommand" -a "check" -d "Check if environment needs setup"
        complete -c macdev -n "__fish_use_subcommand" -a "upgrade" -d "Upgrade packages"
        complete -c macdev -n "__fish_use_subcommand" -a "tap" -d "Add a Homebrew tap"
        complete -c macdev -n "__fish_use_subcommand" -a "untap" -d "Remove a Homebrew tap"
        complete -c macdev -n "__fish_use_subcommand" -a "completion" -d "Generate shell completion script"
        complete -c macdev -n "__fish_use_subcommand" -a "help" -d "Show help message"
        complete -c macdev -n "__fish_use_subcommand" -a "version" -d "Show version"

        complete -c macdev -n "__fish_seen_subcommand_from completion" -a "bash zsh fish"
      FISH
    end
  end
end
