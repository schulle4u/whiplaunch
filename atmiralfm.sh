#!/bin/bash
# ATMIRAL File Browser
# A part of ATMIRAL - Accessible text-based menu interface for running applications on Linux
# Copyright (c) 2025 Steffen Schultz, released under the terms of the MIT license

set -uo pipefail

# Determine current script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration values
ATMIRAL_LANG=""
SHOW_HIDDEN=1
DEFAULT_EDITOR="nano"
DEFAULT_VIEWER="less"
DEFAULT_PLAYER="mpv"
DEFAULT_IMG_VIEWER="feh"

# Load config file
CONFIG_FILE=""
if [ -e "/etc/atmiral/atmiral.conf" ]; then
    CONFIG_FILE="/etc/atmiral/atmiral.conf"
elif [ -e "$HOME/.config/atmiral/atmiral.conf" ]; then
    CONFIG_FILE="$HOME/.config/atmiral/atmiral.conf"
elif [ -e "$SCRIPT_DIR/atmiral.conf" ]; then
    CONFIG_FILE="$SCRIPT_DIR/atmiral.conf"
fi

if [ -n "$CONFIG_FILE" ]; then
    # Check if config file is readable
    if [ -r "$CONFIG_FILE" ]; then
        if grep -q -vE '^\s*(#|$|[a-zA-Z_][a-zA-Z0-9_]*=)' "$CONFIG_FILE"; then
            echo "Error: Config file '$CONFIG_FILE' contains invalid lines." >&2
            exit 1
        fi
        if ! (set -e; source "$CONFIG_FILE") 2>/dev/null; then
            echo "Error: Invalid config file '$CONFIG_FILE'." >&2
            exit 1
        fi
    else
        echo "Error: Cannot read config file '$CONFIG_FILE'." >&2
        exit 1
    fi
fi

# Initialize GNU gettext after loading configuration.
# shellcheck source=lib/i18n.sh
I18N_LIB="$SCRIPT_DIR/lib/i18n.sh"
if [[ ! -f "$I18N_LIB" ]]; then I18N_LIB="$HOME/.local/share/atmiral/lib/i18n.sh"; fi
if [[ ! -f "$I18N_LIB" ]]; then I18N_LIB="/usr/local/share/atmiral/lib/i18n.sh"; fi
if [[ ! -r "$I18N_LIB" ]]; then
    echo "Error: Cannot load the ATMIRAL gettext runtime." >&2
    exit 1
fi
# shellcheck source=lib/i18n.sh
source "$I18N_LIB"
if ! command -v gettext >/dev/null 2>&1; then
    echo "Error: GNU gettext is required." >&2
    exit 1
fi
atmiral_init_i18n "$SCRIPT_DIR" "$ATMIRAL_LANG"

# Dependency Check
check_dependencies() {
    if ! command -v dialog >/dev/null 2>&1; then
        printf "%s\n" "$(_ "Error: dialog is not installed.")" >&2
        printf "%s\n" "$(_ "Install using e.g.: sudo apt install dialog")" >&2
        exit 1
    fi
    if ! command -v file >/dev/null 2>&1; then
        printf "%s\n" "$(_ "Error: The file command is missing.")" >&2
        exit 1
    fi
}

check_dependencies

# Set initial options for dialog
export DIALOGOPTS="--visit-items --no-lines \
    --ok-label \"$(_ "OK")\" \
    --yes-label \"$(_ "Yes")\" \
    --no-label \"$(_ "No")\" \
    --cancel-label \"$(_ "Cancel")\""

# Set starting directory and fallback
if [[ -n "${1:-}" && -d "$1" ]]; then
    CWD="$1"
elif [[ -d "$HOME" ]]; then
    CWD="$HOME"
else
    CWD=$SCRIPT_DIR
fi

# Translate some expected exit codes into human-readable messages
exit_code_to_message() {
    if [[ -z "$1" ]]; then
        local exit_code=$?
    else
        local exit_code=$1
    fi

    if ! [[ "$exit_code" =~ ^[0-9]+$ ]]; then
        printf "$(_ "Invalid exit code '%s'. It must be a positive integer.")" "$exit_code" >&2
        return 1
    fi

    case $exit_code in
        0)
            echo "$(_ "Command successful.")"
            ;;
        1)
            echo "$(_ "Error executing command: General error.")"
            ;;
        2)
            echo "$(_ "Error: Wrong usage of arguments.")"
            ;;
        126)
            echo "$(_ "Error: Insufficient permissions.")"
            ;;
        127)
            echo "$(_ "Error: Command not found.")"
            ;;
        *)
            printf "$(_ "Error: Exit code '%d'")" "$exit_code"
            ;;
    esac
}

# Get mimetype
get_safe_mimetype() {
    local filepath="$1"
    local mimetype=""
    
    # Check if path exists
    if [[ ! -e "$filepath" && ! -L "$filepath" ]]; then
        echo "$(_ "File not found")"
        return 1
    fi
    
    # Handle symbolic links
    if [[ -L "$filepath" ]]; then
        local link_target
        link_target=$(readlink "$filepath" 2>/dev/null)
        if [[ $? -ne 0 || -z "$link_target" ]]; then
            echo "$(_ "Broken link %s")"
            return 1
        fi
        
        # Check if link is absolute or relative
        if [[ "$link_target" != /* ]]; then
            # Relative link - combine with original directory
            local dir=$(dirname "$filepath")
            link_target="$dir/$link_target"
        fi
        
        # Check link target
        if [[ ! -e "$link_target" ]]; then
            echo "$(_ "Broken link %s")"
            return 1
        elif [[ -d "$link_target" ]]; then
            echo "$(_ "Directory link")"
            return 0
        elif [[ -f "$link_target" ]]; then
            echo "$(_ "File link")"
            return 0
        else
            echo "$(_ "special file")"
            return 0
        fi
    fi
    
    # Handle special file types
    if [[ -d "$filepath" ]]; then
        echo "$(_ "Folder")"
        return 0
    elif [[ -c "$filepath" ]]; then
        echo "$(_ "Character device")"
        return 0
    elif [[ -b "$filepath" ]]; then
        echo "$(_ "Block device")"
        return 0
    elif [[ -p "$filepath" ]]; then
        echo "$(_ "Named Pipe")"
        return 0
    elif [[ -S "$filepath" ]]; then
        echo "$(_ "Socket")"
        return 0
    elif [[ ! -f "$filepath" ]]; then
        echo "$(_ "special file")"
        return 1
    fi
    
    # Check read permissions for regular files
    if [[ ! -r "$filepath" ]]; then
        echo "$(_ "No read permission")"
        return 1
    fi
    
    # Try to get mimetype
    if command -v file >/dev/null 2>&1; then
        # Timeout and error handling
        mimetype=$(timeout 5s file --mime-type -b "$filepath" 2>/dev/null)
        local exit_code=$?
        
        # Check if command successful
        if [[ $exit_code -eq 0 && -n "$mimetype" ]]; then
            # Clean unusual output
            mimetype=$(echo "$mimetype" | tr -d '\0\r\n' | cut -d';' -f1)
            
            # Validate MIME-Type Format (type/subtype)
            if [[ "$mimetype" =~ ^[a-zA-Z][a-zA-Z0-9][a-zA-Z0-9\!\#\$\&\-\^]*\/[a-zA-Z0-9][a-zA-Z0-9\!\#\$\&\-\^\.]*$ ]]; then
                echo "$mimetype"
                return 0
            fi
        elif [[ $exit_code -eq 124 ]]; then
            # Timeout exceded
            echo "$(_ "Timeout while getting file type")"
            return 1
        fi
    fi
    
    # Fallback: Check file extension
    get_mimetype_by_extension "$filepath"
    return $?
}

# Fallback for mimetype detection using file extension
get_mimetype_by_extension() {
    local filepath="$1"
    local filename=$(basename "$filepath")
    local extension="${filename##*.}"
    
    # Convert to lowercase
    extension=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
    
    case "$extension" in
        # Text files
        txt|text) echo "text/plain" ;;
        md|markdown) echo "text/markdown" ;;
        html|htm) echo "text/html" ;;
        css) echo "text/css" ;;
        js) echo "text/javascript" ;;
        json) echo "application/json" ;;
        xml) echo "text/xml" ;;
        csv) echo "text/csv" ;;
        
        # Images
        jpg|jpeg) echo "image/jpeg" ;;
        png) echo "image/png" ;;
        gif) echo "image/gif" ;;
        bmp) echo "image/bmp" ;;
        svg) echo "image/svg+xml" ;;
        webp) echo "image/webp" ;;
        
        # Audio
        mp3) echo "audio/mpeg" ;;
        wav) echo "audio/wav" ;;
        ogg) echo "audio/ogg" ;;
        flac) echo "audio/flac" ;;
        
        # Video
        mp4) echo "video/mp4" ;;
        avi) echo "video/x-msvideo" ;;
        mkv) echo "video/x-matroska" ;;
        webm) echo "video/webm" ;;
        
        # Archive
        zip) echo "application/zip" ;;
        tar) echo "application/x-tar" ;;
        gz) echo "application/gzip" ;;
        bz2) echo "application/x-bzip2" ;;
        
        # Documents
        pdf) echo "application/pdf" ;;
        doc) echo "application/msword" ;;
        docx) echo "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ;;
        
        # Executable
        sh|bash) echo "application/x-shellscript" ;;
        py) echo "text/x-python" ;;
        
        *) echo "application/octet-stream" ;;
    esac
    return 0
}
# Save current selection
current_selection=""

# Dialog wrapper
run_dialog() {
    local output
    local exit_code
    output=$(dialog "$@" 3>&1 1>&2 2>&3)
    exit_code=$?
    printf '%s\n' "$output"
    return $exit_code
}

# Actions menu
show_actions() {
    local current_entry=$1
    
    # Check if entry exists
    if [[ ! -e "$current_entry" ]]; then
        run_dialog --msgbox "$(printf "$(_ "File not found")" "$current_entry")" 10 70
        return
    fi
    
    actions=()
    
    if [[ -d "$current_entry" ]]; then
        # Directory actions
        actions+=("open" "$(_ "Open directory")")
        actions+=("copy" "$(_ "Copy to")")
        actions+=("move" "$(_ "Move to")")
        actions+=("delete" "$(_ "Delete")")
        actions+=("info" "$(_ "File info")")
    else
        # File actions - existing logic
        local mimetype=$(file --mime-type -b "$current_entry" 2>/dev/null || echo "application/octet-stream")

        if [[ $mimetype == text/* ]]; then
            if command -v "$DEFAULT_EDITOR" >/dev/null 2>&1; then
                actions+=("editor" "$(printf "$(_ "Open with %s as text")" "$DEFAULT_EDITOR")")
            fi
            if command -v "$DEFAULT_VIEWER" >/dev/null 2>&1; then
                actions+=("viewer" "$(printf "$(_ "View with %s")" "$DEFAULT_VIEWER")")
            fi
        fi
        if [[ $mimetype == audio/* || $mimetype == video/* ]]; then
            if command -v "$DEFAULT_PLAYER" >/dev/null 2>&1; then
                actions+=("player" "$(printf "$(_ "Play with %s")" "$DEFAULT_PLAYER")")
            fi
        fi
        if [[ $mimetype == image/* ]]; then
            if command -v "$DEFAULT_IMG_VIEWER" >/dev/null 2>&1; then
                actions+=("imageviewer" "$(printf "$(_ "View with %s")" "$DEFAULT_IMG_VIEWER")")
            fi
        fi
        if [[ -x "$current_entry" ]]; then
            actions+=("run" "$(_ "Run")")
        fi
        actions+=("custom" "$(_ "Open with")")
        actions+=("copy" "$(_ "Copy to")")
        actions+=("move" "$(_ "Move to")")
        actions+=("delete" "$(_ "Delete")")
        actions+=("info" "$(_ "File info")")
    fi
    
    actions+=("cancel" "$(_ "Cancel")")

    # File/Directory actions menu
    clear
    local item_type
    if [[ -d "$current_entry" ]]; then
        item_type="$(_ "Folder")"
    else
        item_type="$(_ "File")"
    fi

    if ! action=$(run_dialog --title "$(printf "$(_ "%s: %s")" "$item_type" "$(basename "$current_entry")")" \
        --no-tags \
        --menu "$(_ "Please select an action and press enter to confirm:")" 0 0 0 \
        "${actions[@]}"); then
            return
        fi

    case $action in
        "open")
            if [[ -d "$current_entry" ]]; then
                CWD="$current_entry"
            fi
            ;;
        "editor") ("$DEFAULT_EDITOR" "$current_entry") ;;
        "viewer") ("$DEFAULT_VIEWER" "$current_entry") ;;
        "player") ("$DEFAULT_PLAYER" "$current_entry") ;;
        "imageviewer") ("$DEFAULT_IMG_VIEWER" "$current_entry") ;;
        "run") ("$current_entry") ;;
        "custom")
            clear
            if ! custom_cmd=$(run_dialog --title "$(_ "Open with")" \
                --inputbox "$(_ "Please enter command (parameters allowed):")" 10 60); then
                return
            fi

            if [ -n "$custom_cmd" ]; then
                # Split into command and parameters
                quoted_parts=()
                for word in $custom_cmd; do
                    quoted_parts+=("$(printf '%q' "$word")")
                done

                # Quote and attach file safely
                quoted_parts+=("$(printf '%q' "$current_entry")")

                # Re-build and run command
                (bash -c "${quoted_parts[*]}")
                local exit_code=$?
                local exit_message=$(exit_code_to_message "$exit_code")
                if [[ ! $exit_code -eq 0 ]]; then
                    clear
                    run_dialog --msgbox "$exit_message" 10 70
                fi
            else
                clear
                run_dialog --msgbox "$(_ "Error: Input cannot be empty.")" 10 70
            fi
            ;;
        "copy")
            clear
            if ! copy_cmd=$(run_dialog --title "$(_ "Copy to")" --fselect "$HOME/" 15 70); then
                return
            fi

            if [[ -d "$current_entry" ]]; then
                (cp -r "$current_entry" "$copy_cmd")
            else
                (cp "$current_entry" "$copy_cmd")
            fi
            local exit_code=$?
            local exit_message=$(exit_code_to_message "$exit_code")
            clear
            run_dialog --msgbox "$exit_message" 10 70
            ;;
        "move")
            clear
            if ! move_cmd=$(run_dialog --title "$(_ "Move to")" --fselect "$HOME/" 15 70); then
                return
            fi
            
            (mv "$current_entry" "$move_cmd")
            local exit_code=$?
            local exit_message=$(exit_code_to_message "$exit_code")
            clear
            run_dialog --msgbox "$exit_message" 10 70
            ;;
        "delete")
            clear
            local item_type
            if [[ -d "$current_entry" ]]; then
                item_type="$(_ "Folder")"
            else
                item_type="$(_ "File")"
            fi
            
            if run_dialog --title "$(_ "Delete")" --yesno "$(printf "$(_ "Should %s '%s' be deleted?")" "$item_type" "$(basename "$current_entry")")" 15 70; then
                if [[ -d "$current_entry" ]]; then
                    (rm -rf "$current_entry")
                else
                    (rm "$current_entry")
                fi
                local exit_code=$?
                local exit_message=$(exit_code_to_message "$exit_code")
                clear
                run_dialog --msgbox "$exit_message" 10 70
            fi
            ;;
        "info")
            clear
            # Using get_safe_mimetype for the detailed information
            local detailed_info
            detailed_info=$(get_safe_mimetype "$current_entry")
            
            info_message=$(printf "$(_ "Path: %s")" "$current_entry\n")
            info_message+="---------------------------------\n"
            info_message+=$(printf "$(_ "Type: %s")" "$detailed_info\n")
            info_message+=$(printf "$(_ "File size: %s")" "$(du -sh "$current_entry" 2>/dev/null | awk '{print $1}')\n")
            info_message+=$(printf "$(_ "Permissions: %s")" "$(stat -c '%A (%U:%G)' "$current_entry" 2>/dev/null)\n")

            run_dialog --title "$(_ "File info")" --msgbox "$info_message" 0 0
            ;;
        *)
            return
            ;;
    esac
}

# Trap to handle cleanup on script exit
cleanup() {
    clear
    printf '%s\n' "$(_ "Exited ATMIRAL.")"
}
trap cleanup EXIT

while true; do
    # List entries
    entries=()
    entries+=(".." "$(_ "Parent level")")

    # Command for finding directories (excluding . and ..)
    find_dirs=(find "$CWD" -maxdepth 1 -mindepth 1 -type d)

    # Command for finding regular files and special files
    find_files=(find "$CWD" -maxdepth 1 -mindepth 1 -not -type d)
    
    # Add hidden file exclusion
    if [[ "$SHOW_HIDDEN" != "1" ]]; then
        find_dirs+=(-not -name '.*')
        find_files+=(-not -name '.*')
    fi
    
    # Process directories
    # Sort them alphabetically
    while IFS= read -r -d '' dir_path; do
        # local name
        name=$(basename "$dir_path")
        if [[ -L "$dir_path" ]]; then
            entries+=("$name" "$(_ "symbolic link")")
        else
            entries+=("$name" "$(_ "Folder")")
        fi
    done < <("${find_dirs[@]}" -print0 | sort -z)

    # Process files
    # Sort them alphabetically
    while IFS= read -r -d '' file_path; do
        # local name
        name=$(basename "$file_path")
        if [[ -L "$file_path" ]]; then
            entries+=("$name" "$(_ "symbolic link")")
        elif [[ -c "$file_path" || -b "$file_path" || -p "$file_path" || -S "$file_path" ]]; then
            entries+=("$name" "$(_ "special file")")
        else
            entries+=("$name" "$(_ "File")")
        fi
    done < <("${find_files[@]}" -print0 | sort -z)

    # Main menu
    clear
    choice=$(run_dialog --begin 3 1 \
        --backtitle "$(_ "ATMIRAL file browser") - ${USER}@${HOSTNAME}:${CWD}" \
        --extra-button --extra-label "$(_ "Actions")" \
        --title "$(_ "Folder content")" \
        --ok-label "$(_ "Select")" \
        --cancel-label "$(_ "Exit")" \
        --default-item "$current_selection" \
        --menu "$(_ "Select an item with your arrow keys and use enter to confirm:")" 0 0 0 \
        "${entries[@]}")

    dialog_exit=$?
    case $dialog_exit in
        0)
            if [ "$choice" = ".." ]; then
                # Back to parent
                CWD=$(dirname "$CWD")
                continue
            fi

            if [ -d "$CWD/$choice" ]; then
                # Check read permissions
                if [[ ! -r "$CWD/$choice" ]]; then
                    run_dialog --msgbox "$(_ "No read permission")" 10 70
                   continue
                fi

                # Jump into subfolder
                current_selection="$choice"
                CWD="$CWD/$choice"
                continue
            else
                current_selection="$choice"
                show_actions "$CWD/$choice"
            fi
            ;;
        3)
            if [[ -n "$choice" && "$choice" != ".." ]]; then
                current_selection="$choice"
                show_actions "$CWD/$choice"
            else
                run_dialog --msgbox "$(_ "No selection")" 10 70
            fi
            ;;
        1|255)
            break
            ;;
        *)
            break
            ;;
    esac
done
