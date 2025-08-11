#!/bin/bash

# Build script for Rust tokenizer FFI
# This script is called by Xcode during the build process

set -e

# Add Homebrew and Rust to PATH (Xcode doesn't inherit shell PATH)
# Include both common Rust installation paths
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.cargo/bin:$PATH"

# Verify cargo is available
if ! command -v cargo &> /dev/null; then
    echo "Error: cargo not found. Please install Rust from https://rustup.rs"
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
RUST_PROJECT_DIR="$PROJECT_DIR/TokenizerFFI"

echo "Building Rust tokenizer library..."

# Change to Rust project directory
cd "$RUST_PROJECT_DIR"

# For simplicity, just build for the native architecture
# The library is already built, but this ensures it stays up to date
cargo build --release

echo "Rust tokenizer library built successfully"