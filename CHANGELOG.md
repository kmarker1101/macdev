# Changelog

All notable changes to macdev will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-11-21

### Added
- Project-isolated development environments using Homebrew
- Pure (isolated) and impure (system-wide) package management
- Automatic Python virtual environment creation
- Support for multiple Python versions per project
- Python symlink normalization (both `python` and `python3` work)
- Lock files for reproducible environments
- Homebrew cask support for GUI applications (`--cask` flag)
- Shell completion for bash, zsh, and fish
- `macdev gc --all` flag to remove all pure packages
- `macdev upgrade` command to upgrade packages
- `macdev check --quiet` for fast environment validation
- direnv integration
- Homebrew tap management
- Project-specific package listing in `macdev list`

### Technical
- Refactored to library + binary structure for better testability
- Versioned packages use full spec as key in global manifest
- Lock files only include project-specific packages (not global)
- Proper Python symlink creation for venv support

[Unreleased]: https://github.com/kmarker1101/macdev/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kmarker1101/macdev/releases/tag/v0.1.0
