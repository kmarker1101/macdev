# frozen_string_literal: true

module Macdev
  # Command-line interface router
  class CLI
    HELP_TEXT = <<~HELP.freeze
      macdev #{VERSION}
      Project-isolated development environments on macOS using Homebrew

      USAGE:
          macdev <COMMAND>

      COMMANDS:
          init                 Initialize a new project
          add <packages>...    Add packages to environment
          remove <packages>... Remove packages
          install              Install packages from manifest
          shell                Enter isolated shell
          list                 List installed packages
          sync                 Sync packages from manifest(s)
          gc                   Garbage collect unused packages
          check                Check if environment needs setup
          upgrade [package]    Upgrade packages
          tap <tap>            Add a Homebrew tap
          untap <tap>          Remove a Homebrew tap
          completion <shell>   Generate shell completion script
          help                 Show this help message
          version              Show version

      FLAGS:
          --impure             Install package system-wide (for add)
          --cask               Install as a cask (for add)
          --all                Remove all pure packages (for gc)
          --quiet              Suppress output (for check)

      See 'macdev help <command>' for more information on a specific command.
    HELP

    def self.run(args)
      command = args.shift

      case command
      when 'init'       then Manifest.init
      when 'add'        then handle_add(args)
      when 'install'    then Environment.install
      when 'remove'     then handle_remove(args)
      when 'gc'         then Environment.gc(args.delete('--all'))
      when 'sync'       then Environment.sync
      when 'check'      then Environment.check(args.delete('--quiet'))
      when 'upgrade'    then Environment.upgrade(args.shift)
      when 'list'       then Manifest.list
      when 'shell'      then Environment.shell
      when 'tap'        then handle_tap(args)
      when 'untap'      then handle_untap(args)
      when 'completion' then handle_completion(args)
      when 'version', '--version', '-v' then puts "macdev #{VERSION}"
      when 'help', '--help', '-h', nil  then show_help
      else
        puts "Unknown command: #{command}"
        show_help
        exit 1
      end
    end

    def self.show_help
      puts HELP_TEXT
    end

    private_class_method def self.handle_add(args)
      impure = args.delete('--impure')
      cask = args.delete('--cask')

      abort "\e[31mError: No packages specified\e[0m" if args.empty?

      args.each { |pkg| Environment.add(pkg, impure: impure, cask: cask) }
    end

    private_class_method def self.handle_remove(args)
      abort "\e[31mError: No packages specified\e[0m" if args.empty?

      args.each { |pkg| Environment.remove(pkg) }
    end

    private_class_method def self.handle_tap(args)
      abort "\e[31mError: No tap specified\e[0m" if args.empty?

      Environment.tap(args.shift)
    end

    private_class_method def self.handle_untap(args)
      abort "\e[31mError: No tap specified\e[0m" if args.empty?

      Environment.untap(args.shift)
    end

    private_class_method def self.handle_completion(args)
      abort "\e[31mError: No shell specified\e[0m" if args.empty?

      Completion.generate(args.shift)
    end
  end
end
