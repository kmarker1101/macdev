# Build and install macdev

# Default recipe - show available commands
default:
    @just --list

# Build debug version
build:
    cargo build

# Build release version
release:
    cargo build --release

# Install release binary to ~/bin/
install: release
    cp target/release/macdev ~/bin/
    @echo "✓ Installed macdev to ~/bin/"

# Run tests
test:
    cargo test

# Check code without building
check:
    cargo check

# Run clippy lints
lint:
    cargo clippy

# Clean build artifacts
clean:
    cargo clean

# Format code
fmt:
    cargo fmt

# Build and run with args (e.g., just run init)
run *args:
    cargo run -- {{args}}
