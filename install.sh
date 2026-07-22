#!/bin/bash
# ATMIRAL Installation Script
# Copyright (c) 2025 Steffen Schultz, released under the terms of the MIT license

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROGRAM_NAME="atmiral"
VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_usage() {
    cat << EOF
ATMIRAL Installation Script v${VERSION}

Usage: $0 [OPTION]

Options:
  --system     Install system-wide (requires sudo)
  --user       Install for current user only
  --both       Install system-wide and setup user config
  --uninstall  Remove ATMIRAL installation
  --help       Show this help message

Installation paths:
  System:      /usr/local/bin, /usr/local/share, /etc
  User:        ~/.local/bin, ~/.local/share, ~/.config

Examples:
  $0 --system     # Install for all users (needs sudo)
  $0 --user       # Install for current user
  $0 --both       # Install system + user config
  $0 --uninstall  # Remove installation

EOF
}

# Check dependencies
check_dependencies() {
    local missing_deps=()

    if ! command -v dialog >/dev/null 2>&1; then
        missing_deps+=("dialog")
    fi

    if ! command -v gettext >/dev/null 2>&1; then
        missing_deps+=("gettext")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_info "Install with: sudo apt install ${missing_deps[*]}"
        exit 1
    fi
}

# Check if required files exist
check_source_files() {
    local missing_files=()

    [[ ! -f "$SCRIPT_DIR/${PROGRAM_NAME}.sh" ]] && missing_files+=("${PROGRAM_NAME}.sh")
    [[ ! -f "$SCRIPT_DIR/atmiralfm.sh" ]] && missing_files+=("atmiralfm.sh")
    [[ ! -f "$SCRIPT_DIR/lib/i18n.sh" ]] && missing_files+=("lib/i18n.sh")
    [[ ! -f "$SCRIPT_DIR/locale/de/LC_MESSAGES/atmiral.mo" ]] && missing_files+=("locale/de/LC_MESSAGES/atmiral.mo")
    [[ ! -d "$SCRIPT_DIR/menu" ]] && missing_files+=("menu/")

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_error "Missing source files: ${missing_files[*]}"
        print_info "Please run this script from the ATMIRAL source directory"
        exit 1
    fi
}

# Create directory with proper permissions
create_dir() {
    local dir="$1"
    local mode="${2:-755}"

    if [[ ! -d "$dir" ]]; then
        print_info "Creating directory: $dir"
        mkdir -p "$dir" || return 1
    fi
    chmod "$mode" "$dir"
}

# Copy file with proper permissions
copy_file() {
    local src="$1"
    local dst="$2"
    local mode="${3:-644}"

    print_info "Copying: $(basename "$src") -> $dst"
    if [ -d "$dst" ]; then
        local filename
        filename=$(basename "$src")
        cp "$src" "$dst/$filename" || return 1
        chmod "$mode" "$dst/$filename"
    else
        cp "$src" "$dst" || return 1
        if [ -f "$dst" ]; then
            chmod "$mode" "$dst"
        fi
    fi
}

# Install system-wide
install_system() {
    if [[ $EUID -ne 0 ]]; then
        print_error "System installation requires root privileges"
        print_info "Run with: sudo $0 --system"
        exit 1
    fi

    print_info "Installing ATMIRAL system-wide..."

    # Create directories
    create_dir "/usr/local/bin"
    create_dir "/usr/local/share/${PROGRAM_NAME}"
    create_dir "/usr/local/share/locale/de/LC_MESSAGES"
    create_dir "/usr/local/share/${PROGRAM_NAME}/menu"
    create_dir "/etc/${PROGRAM_NAME}"

    # Install main script
    copy_file "$SCRIPT_DIR/${PROGRAM_NAME}.sh" "/usr/local/bin/${PROGRAM_NAME}" 755

    # Install file browser
    copy_file "$SCRIPT_DIR/atmiralfm.sh" "/usr/local/bin/atmiralfm" 755

    # Install gettext runtime and compiled catalog
    create_dir "/usr/local/share/${PROGRAM_NAME}/lib"
    copy_file "$SCRIPT_DIR/lib/i18n.sh" "/usr/local/share/${PROGRAM_NAME}/lib/" 644
    copy_file "$SCRIPT_DIR/locale/de/LC_MESSAGES/atmiral.mo" "/usr/local/share/locale/de/LC_MESSAGES/" 644

    # Install example menu files
    for menu_file in "$SCRIPT_DIR"/menu/*.txt; do
        [[ -f "$menu_file" ]] || continue
        copy_file "$menu_file" "/usr/local/share/${PROGRAM_NAME}/menu/"
    done

    # Install configuration file
    if [[ -f "$SCRIPT_DIR/${PROGRAM_NAME}.conf" ]]; then
        if [[ ! -f "/etc/${PROGRAM_NAME}/${PROGRAM_NAME}.conf" ]]; then
            copy_file "$SCRIPT_DIR/${PROGRAM_NAME}.conf" "/etc/${PROGRAM_NAME}/"
        else
            print_warning "System config already exists, not overwriting"
        fi
    fi

    print_success "System installation completed"
    print_info "ATMIRAL is now available as '${PROGRAM_NAME}' command"
}

# Install for user
install_user() {
    print_info "Installing ATMIRAL for user: $USER"

    # Create directories
    create_dir "$HOME/.local/bin"
    create_dir "$HOME/.local/share/${PROGRAM_NAME}"
    create_dir "$HOME/.local/share/locale/de/LC_MESSAGES"
    create_dir "$HOME/.local/share/${PROGRAM_NAME}/menu"
    create_dir "$HOME/.config/${PROGRAM_NAME}"
    create_dir "$HOME/.config/${PROGRAM_NAME}/menu"

    # Install main script
    copy_file "$SCRIPT_DIR/${PROGRAM_NAME}.sh" "$HOME/.local/bin/${PROGRAM_NAME}" 755

    # Install file browser
    copy_file "$SCRIPT_DIR/atmiralfm.sh" "$HOME/.local/bin/atmiralfm" 755

    # Install gettext runtime and compiled catalog
    create_dir "$HOME/.local/share/${PROGRAM_NAME}/lib"
    copy_file "$SCRIPT_DIR/lib/i18n.sh" "$HOME/.local/share/${PROGRAM_NAME}/lib/" 644
    copy_file "$SCRIPT_DIR/locale/de/LC_MESSAGES/atmiral.mo" "$HOME/.local/share/locale/de/LC_MESSAGES/" 644

    # Install example menu files
    for menu_file in "$SCRIPT_DIR"/menu/*.txt; do
        [[ -f "$menu_file" ]] || continue
        copy_file "$menu_file" "$HOME/.local/share/${PROGRAM_NAME}/menu/"
    done

    # Install user configuration file
    if [[ -f "$SCRIPT_DIR/${PROGRAM_NAME}.conf" ]]; then
        if [[ ! -f "$HOME/.config/${PROGRAM_NAME}/${PROGRAM_NAME}.conf" ]]; then
            copy_file "$SCRIPT_DIR/${PROGRAM_NAME}.conf" "$HOME/.config/${PROGRAM_NAME}/"
        else
            print_warning "User config already exists, not overwriting"
        fi
    fi

    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        # The tilde is intentionally displayed literally to the user.
        # shellcheck disable=SC2088
        print_warning "~/.local/bin is not in your PATH"
        print_info "Add this line to your ~/.bashrc or ~/.profile:"
        print_info "export PATH=\"\$HOME/.local/bin:\$PATH\""
        print_info "Then run: source ~/.bashrc"
    fi

    print_success "User installation completed"
    print_info "ATMIRAL is available as '${PROGRAM_NAME}' command (if PATH is set correctly)"
}

# Setup user configuration (for --both option)
setup_user_config() {
    print_info "Setting up user configuration for: $USER"

    # Create user config directories
    create_dir "$HOME/.config/${PROGRAM_NAME}"
    create_dir "$HOME/.config/${PROGRAM_NAME}/menu"

    # Install user configuration file if it doesn't exist
    if [[ -f "$SCRIPT_DIR/${PROGRAM_NAME}.conf" ]]; then
        if [[ ! -f "$HOME/.config/${PROGRAM_NAME}/${PROGRAM_NAME}.conf" ]]; then
            copy_file "$SCRIPT_DIR/${PROGRAM_NAME}.conf" "$HOME/.config/${PROGRAM_NAME}/"
        else
            print_warning "User config already exists, not overwriting"
        fi
    fi

    print_success "User configuration setup completed"
}

# Uninstall ATMIRAL
uninstall() {
    print_info "Uninstalling ATMIRAL..."

    local removed_items=()

    # Remove system files (if running as root)
    if [[ $EUID -eq 0 ]]; then
        if [[ -f "/usr/local/bin/${PROGRAM_NAME}" && -f "/usr/local/bin/atmiralfm" ]]; then
            rm -f "/usr/local/bin/${PROGRAM_NAME}"
            rm -f "/usr/local/bin/atmiralfm"
            removed_items+=("System binary")
        fi

        if [[ -d "/usr/local/share/${PROGRAM_NAME}" ]]; then
            rm -rf "/usr/local/share/${PROGRAM_NAME}"
            removed_items+=("System data")
        fi

        if [[ -d "/etc/${PROGRAM_NAME}" ]]; then
            read -p "Remove system configuration in /etc/${PROGRAM_NAME}? [y/N]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "/etc/${PROGRAM_NAME:?}"
                removed_items+=("System config")
            fi
        fi
    fi

    # Remove user files
    if [[ -f "$HOME/.local/bin/${PROGRAM_NAME}" && -f "$HOME/.local/bin/atmiralfm" ]]; then
        rm -f "$HOME/.local/bin/${PROGRAM_NAME}"
        rm -f "$HOME/.local/bin/atmiralfm"
        removed_items+=("User binary")
    fi

    if [[ -d "$HOME/.local/share/${PROGRAM_NAME}" ]]; then
        rm -rf "$HOME/.local/share/${PROGRAM_NAME}"
        removed_items+=("User data")
    fi

    if [[ -d "$HOME/.config/${PROGRAM_NAME}" ]]; then
        read -p "Remove user configuration in ~/.config/${PROGRAM_NAME}? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$HOME/.config/${PROGRAM_NAME}"
            removed_items+=("User config")
        fi
    fi

    if [[ ${#removed_items[@]} -gt 0 ]]; then
        print_success "Removed: ${removed_items[*]}"
    else
        print_warning "No ATMIRAL installation found"
    fi
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 0
    fi

    case "$1" in
        --system)
            check_source_files
            check_dependencies
            install_system
            ;;
        --user)
            check_source_files
            check_dependencies
            install_user
            ;;
        --both)
            check_source_files
            check_dependencies
            install_system
            setup_user_config
            ;;
        --uninstall)
            uninstall
            ;;
        --help)
            print_usage
            ;;
        *)
            print_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
