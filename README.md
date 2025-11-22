# macdev

**The problem:** I have been using Nix for a couple of years and it has been great. I just wanted to try my hand at building something similar on Mac without having to create yet another package manager. This is the result of Claude and I doing some Vibe coding.

**The solution:** macdev provides Nix-like environment isolation using Homebrew, allowing you to have different versions of tools per project while keeping your system clean.

## Status
**Alpha software.** I built this for my own consulting work and it's been fairly solid for me. That said, expect rough edges and breaking changes.

## Demo

[![asciicast](https://asciinema.org/a/osBgT3woq3wepUL4ORatFxnlV.svg)](https://asciinema.org/a/osBgT3woq3wepUL4ORatFxnlV)

## Features

- 🔒 **Project isolation** - Each project gets its own isolated environment
- 📦 **Pure packages** - Installed packages are isolated to `.macdev/profile`
- 🌍 **Impure packages** - System-wide packages for global tools
- 🖥️ **Cask support** - Install GUI applications (Chrome, VS Code, etc.)
- 🔐 **Lock files** - Reproducible environments with exact dependency versions
- 🗑️ **Garbage collection** - Clean up unused packages automatically
- 🐍 **Python venvs** - Automatic virtual environment creation for Python projects
- 🐍 **Multiple Python versions** - Each project can use different Python versions
- 🚀 **Shell integration** - Works seamlessly with direnv
- 🔧 **Shell completion** - Tab completion for bash, zsh, fish

## Installation

### Via Homebrew (Recommended)

```bash
brew tap kmarker/macdev
brew install macdev
```

Shell completions are installed automatically via Homebrew.

### Manual Installation

```bash
gem install macdev
```

## Quick Start

```bash
# Initialize a new project
cd my-project
macdev init

# Add packages to your project (isolated)
macdev add python@3.11 rust node

# Install packages from manifest
macdev install

# Enter isolated shell environment
macdev shell

# Or use with direnv (recommended)
echo "use macdev" > .envrc
direnv allow
```

## Core Concepts

### Pure vs Impure Packages

**Pure packages** (default) are isolated to your project:
- Installed without linking to system
- Symlinked to `.macdev/profile/`
- Only available when in project directory or using `macdev shell`
- Tracked in local manifest (`macdev.toml`)

**Impure packages** are installed system-wide:
- Installed normally via Homebrew
- Available everywhere on your system
- Good for tools like git, editors, shells
- Tracked in global manifest (`~/.config/macdev/manifest.toml`)

```bash
# Pure package (project-specific)
macdev add python@3.11

# Impure package (system-wide)
macdev add --impure git emacs
```

### Manifests

**Local manifest** (`macdev.toml`) - Project-specific packages:
```toml
[packages]
python = "3.11"
rust = "*"
node = "*"
```

**Global manifest** (`~/.config/macdev/macdev.toml`) - All managed packages:
```toml
[packages]
python = "3.13"
rust = "*"

[impure]
git = true
emacs = true

[casks]
google-chrome = true
visual-studio-code = true

[gc]
# Packages marked for garbage collection
```

### Lock Files

Lock files (`macdev.lock`) ensure reproducible environments:
- Records exact versions of all packages and dependencies
- Generated automatically on install/add/upgrade
- Should be committed to version control
- Only includes project-specific packages (not global tools)

```toml
[metadata]
generated = "2025-11-20T18:25:24.105781+00:00"
macdev_version = "0.1.0"

[packages.python]
version = "3.11.7"
formula = "python@3.11"

[dependencies."python:readline"]
version = "8.3.1"
formula = "readline"
```

## Commands

### Project Setup

```bash
# Initialize new project
macdev init

# Install packages from manifest
macdev install

# Check if environment is set up
macdev check
macdev check --quiet  # For scripting
```

### Package Management

```bash
# Add pure packages (project-specific)
macdev add python@3.11 rust node

# Add impure packages (system-wide)
macdev add --impure git just direnv

# Add casks (GUI applications, always system-wide)
macdev add --cask google-chrome visual-studio-code

# Remove packages
macdev remove python rust

# List all managed packages (shows project packages first if in a project)
macdev list

# Upgrade packages
macdev upgrade              # Upgrade all
macdev upgrade python@3.11  # Upgrade specific package

# Sync packages from manifest(s)
macdev sync
```

### Homebrew Taps

```bash
# Add a tap
macdev tap homebrew/cask

# Remove a tap
macdev untap homebrew/cask
```

### Cleanup

```bash
# Garbage collect unused packages (packages in gc section)
macdev gc

# Nuclear option - remove ALL pure packages
macdev gc --all
```

### Shell Environment

```bash
# Enter isolated shell
macdev shell

# Exit with Ctrl+D or 'exit'
```

## Shell Integration

### Using with direnv (Recommended)

1. Create `~/.config/direnv/direnvrc`:

```bash
use_macdev() {
  if [[ ! -d .macdev ]]; then
    log_error "No .macdev directory found. Run 'macdev init' first."
    return 1
  fi

  # Quick check if setup is needed
  if ! macdev check --quiet 2>/dev/null; then
    log_status "Setting up macdev environment..."
    macdev install
  fi

  PATH_add .macdev/profile/bin

  # Activate Python venv if it exists
  if [[ -f .macdev/venv/bin/activate ]]; then
    source .macdev/venv/bin/activate
  fi

  export MACDEV_ACTIVE=1
}
```

2. In your project, create `.envrc`:

```bash
use macdev
```

3. Allow direnv:

```bash
direnv allow
```

Now the environment activates automatically when you `cd` into the project!

## Shell Completion

### Zsh

```bash
# User-specific (recommended)
mkdir -p ~/.zsh/completions
macdev completion zsh > ~/.zsh/completions/_macdev

# Add to ~/.zshrc
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

### Bash

```bash
# System-wide
sudo mkdir -p /usr/local/etc/bash_completion.d
macdev completion bash | sudo tee /usr/local/etc/bash_completion.d/macdev

# Or user-specific
macdev completion bash > ~/.bash_completion.d/macdev
# Add to ~/.bashrc: source ~/.bash_completion.d/macdev
```

### Fish

```bash
macdev completion fish > ~/.config/fish/completions/macdev.fish
```

## Python Projects

macdev automatically creates Python virtual environments:

```bash
# Add Python
macdev add python@3.11

# A venv is created at .macdev/venv
# direnv activates it automatically

# Install packages with pip
pip install requests django
```

**Multiple Python versions:**
Each project can use different Python versions:
```bash
# Project A
cd project-a
macdev add python@3.12

# Project B
cd project-b
macdev add python@3.13

# Both versions coexist, isolated per project
```

If Python is upgraded, recreate the venv:

```bash
rm -rf .macdev/venv
macdev install
```

## Casks (GUI Applications)

Install GUI applications system-wide:

```bash
# Add casks
macdev add --cask google-chrome
macdev add --cask visual-studio-code
macdev add --cask docker

# List casks
macdev list

# Remove casks
macdev remove google-chrome
```

**Note:** Casks are always installed system-wide (impure). They can't be project-isolated since they're GUI applications.

## Common Workflows

### New Project

```bash
cd my-project
macdev init
macdev add python@3.11 node rust
echo "use macdev" > .envrc
direnv allow
```

### Joining Existing Project

```bash
git clone https://github.com/team/project
cd project
macdev install  # Installs from macdev.lock
direnv allow
```

### Upgrading Dependencies

```bash
# Upgrade all packages
macdev upgrade

# Regenerate lock file with new versions
git add macdev.lock
git commit -m "Upgrade dependencies"
```

### Cleaning Up

```bash
# Remove package from project
macdev remove old-package

# Garbage collect unused packages
macdev gc
```

## How It Works

1. **Install** - Packages are installed via Homebrew with `brew install`
2. **Unlink** - Pure packages are unlinked from system (`brew unlink`)
3. **Symlink** - Package binaries are symlinked to `.macdev/profile/bin/`
4. **PATH** - Shell prepends `.macdev/profile/bin` to PATH
5. **Isolation** - Only your project sees these specific versions

Dependencies are automatically unlinked if they're not explicitly managed, preventing version conflicts.

## Files & Directories

```
project/
├── macdev.toml        # Local packages (project-specific)
├── macdev.lock        # Lock file (exact versions)
└── .macdev/
    ├── profile/       # Symlinks to package binaries
    │   ├── bin/
    │   └── lib/
    └── venv/          # Python virtual environment (if applicable)

~/.config/macdev/
└── macdev.toml        # Global manifest (all managed packages)
```

## FAQ

**Q: What's the difference between pure and impure?**
Pure packages are project-specific and isolated. Impure packages are system-wide. Use pure for project dependencies, impure for personal tools.

**Q: Should I commit the lock file?**
Yes! The lock file ensures everyone on your team gets the same versions.

**Q: Can I have multiple versions of the same package?**
Yes! Each project can have its own version. For example, project A uses python@3.11, project B uses python@3.12.

**Q: What happens to dependencies?**
Dependencies are tracked in the lock file and automatically unlinked if they're not explicitly managed, preventing conflicts.

**Q: How do I uninstall macdev?**
Remove packages from projects, run `macdev gc`, then delete the binary and `~/.config/macdev/`.

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR.
