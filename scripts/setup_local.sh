#!/bin/bash

# This script attempts to install Terraform, Go, and Make on Linux (Debian/Ubuntu) and macOS.
# Windows users should use the manual commands in commands-to-be-run.md.

set -e

OS="$(uname)"

echo "🕵️ Detecting OS..."

if [ "$OS" = "Darwin" ]; then
    echo "🍎 macOS detected. Using Homebrew..."
    if ! command -v brew &> /dev/null; then
        echo "❌ Homebrew not found. Please install it first: https://brew.sh/"
        exit 1
    fi
    brew install terraform go make
elif [ "$OS" = "Linux" ]; then
    echo "🐧 Linux detected. Using apt..."
    sudo apt update
    sudo apt install -y curl wget gpg lsb-release build-essential

    # Install Terraform
    if ! command -v terraform &> /dev/null; then
        wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update && sudo apt install -y terraform
    fi

    # Install Go
    if ! command -v go &> /dev/null; then
        sudo apt install -y golang-go
    fi
else
    echo "❌ Unsupported OS for automatic setup: $OS"
    echo "Please follow the manual instructions in commands-to-be-run.md"
    exit 1
fi

echo "✅ Local environment setup complete!"
echo "Run 'terraform -version', 'go version', and 'make -v' to verify."
