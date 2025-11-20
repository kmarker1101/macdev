# macdev

** The problem:** Different projects need different tool versions, but managing this on macOS is painful. Homebrew doesn't isolate per-project. Nix has a steep learning curve and doesn't play nice with macOS conventions.

** The solution:** Project-isolated development environments on macOS using Homebrew.

Project-isolated development environments on macOS using Homebrew.

macdev provides Nix-like environment isolation without requiring Nix, allowing you to have different versions of tools per project while keeping your system clean.

## Features

- 🔒 **Project isolation** - Each project gets its own isolated environment
- 📦 **Pure packages** - Installed packages are isolated to `.macdev/profile`
- 🌍 **Impure packages** - System-wide packages for global tools
- 🔐 **Lock files** - Reproducible environments with exact dependency versions
- 🗑️ **Garbage collection** - Clean up unused packages automatically
- 🐍 **Python venvs** - Automatic virtual environment creation for Python projects
- 🚀 **Shell integration** - Works seamlessly with direnv

## Installation

```bash
# Clone and build
git clone https://github.com/yourusername/macdev.git
cd macdev
cargo build --release

# Install binary
cp target/release/macdev /usr/local/bin/

# (Optional) Set up shell completion
macdev completion zsh > ~/.zsh/completions/_macdev
# See "Shell Completion" section for other shells
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
- Tracked in local manifest (`.macdev/manifest.toml`)

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

**Local manifest** (`.macdev/manifest.toml`) - Project-specific packages:
```toml
[packages]
python = "3.11"
rust = "*"
node = "*"
```

**Global manifest** (`~/.config/macdev/manifest.toml`) - All managed packages:
```toml
[packages]
python = "3.11"
rust = "*"

[impure]
git = true
emacs = true

[gc]
# Packages marked for garbage collection
```

### Lock Files

Lock files (`.macdev/manifest.lock`) ensure reproducible environments:
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

# Remove packages
macdev remove python rust

# List all managed packages
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
# Garbage collect unused packages
macdev gc
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

If Python is upgraded, recreate the venv:

```bash
rm -rf .macdev/venv
macdev install
```

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
macdev install  # Installs from manifest.lock
direnv allow
```

### Upgrading Dependencies

```bash
# Upgrade all packages
macdev upgrade

# Regenerate lock file with new versions
git add .macdev/manifest.lock
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
.macdev/
├── manifest.toml      # Local packages (project-specific)
├── manifest.lock      # Lock file (exact versions)
├── profile/           # Symlinks to package binaries
│   ├── bin/
│   └── lib/
└── venv/              # Python virtual environment (if applicable)

~/.config/macdev/
└── manifest.toml      # Global manifest (all managed packages)
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
