#!/bin/bash
# ATMIRAL - Accessible text-based menu interface for running applications on Linux
# Copyright (c) 2025 Steffen Schultz, released under the terms of the MIT license

set -euo pipefail

# Determine current script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration values
ATMIRAL_LANG=""
COMMAND_DEBUG=0

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
}

check_dependencies

# Set initial options for dialog
export DIALOGOPTS="--visit-items --no-lines \
    --backtitle \"$(_ "ATMIRAL") - ${USER}@${HOSTNAME}\" \
    --ok-label \"$(_ "OK")\" \
    --cancel-label \"$(_ "Cancel")\""

# Looking for menu list files
if [[ -n "${1:-}" && -d "$1" ]]; then
    MENUDIR="$1"
elif [[ -d "$HOME/.local/share/atmiral/menu/" ]]; then
    MENUDIR="$HOME/.local/share/atmiral/menu/"
elif [[ -d "/usr/local/share/atmiral/menu/" ]]; then
    MENUDIR="/usr/local/share/atmiral/menu/"
else
    MENUDIR="$SCRIPT_DIR/menu/"
fi

# Validate if directory exists
if [[ ! -d "$MENUDIR" ]]; then
    printf "$(_ "Error: Menu directory '%s' doesn't exist.")\n" "$MENUDIR" >&2
    exit 1
fi

# Parse text format menu files
parse_menufile() {
    local menufile="$1"
    
    if [[ ! -f "$menufile" ]]; then
        printf "$(_ "Warning: File '%s' not found.")\n" "$menufile" >&2
        return 1
    fi
    
    if [[ ! -r "$menufile" ]]; then
        printf "$(_ "Warning: File '%s' not readable.")\n" "$menufile" >&2
        return 1
    fi
    
    PARSED=()
    local line_number=0
    local current_name=""
    local current_desc=""
    local current_cmd=""
    local current_args=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        
        # Remove leading and trailing whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        
        # Parse key-value pairs using localized patterns
        if [[ "$line" =~ ^[Nn]ame:[[:space:]]* ]]; then
            # Save previous entry if complete
            if [[ -n "$current_name" && -n "$current_cmd" ]]; then
                PARSED+=("$current_name" "$current_desc" "$current_cmd" "$current_args")
            fi
            # Start new entry
            current_name=$(echo "$line" | sed "s/^[Nn]ame:[[:space:]]*//")
            current_desc=""
            current_cmd=""
            current_args=""
            
        elif [[ "$line" =~ ^[Dd]escription:[[:space:]]* ]]; then
            current_desc=$(echo "$line" | sed "s/^[Dd]escription:[[:space:]]*//")
            
        elif [[ "$line" =~ ^[Cc]ommand:[[:space:]]* ]]; then
            current_cmd=$(echo "$line" | sed "s/^[Cc]ommand:[[:space:]]*//")
            
        elif [[ "$line" =~ ^[Aa]rguments:[[:space:]]* ]]; then
            current_args=$(echo "$line" | sed "s/^[Aa]rguments:[[:space:]]*//")
            
        else
            printf "$(_ "Warning: Unknown format on line %d: '%s'")\n" "$line_number" "$line" >&2
        fi
    done < "$menufile"
    
    # Don't forget the last entry
    if [[ -n "$current_name" && -n "$current_cmd" ]]; then
        PARSED+=("$current_name" "$current_desc" "$current_cmd" "$current_args")
    fi
    
    if [[ ${#PARSED[@]} -eq 0 ]]; then
        printf "$(_ "Warning: No valid entries found in '%s'.")\n" "$menufile" >&2
        return 1
    fi
    
    return 0
}

# Safe command execution with enhanced argument handling
execute_command() {
    local cmd="$1"
    local args="$2"
    local full_command
    
    if [[ -n "$args" ]]; then
        # Check if arguments contain placeholders or if we should prompt
        if [[ "$args" == *"<"*">"* ]]; then
            # Interactive argument input
            local processed_args="$args"
            local placeholder
            
            # Find all placeholders like <filename>, <path>, etc.
            while [[ "$processed_args" =~ \<([^>]+)\> ]]; do
                placeholder="${BASH_REMATCH[1]}"
                local user_input
                local dialog_type="inputbox"  # default
                
                # Determine dialog type based on placeholder content
                if [[ "$placeholder" =~ ^[Ff]ile ]]; then
                    dialog_type="fselect"
                elif [[ "$placeholder" =~ ^[Dd]irectory ]]; then
                    dialog_type="dselect"
                elif [[ "$placeholder" =~ ^[Pp]assword ]]; then
                    dialog_type="passwordbox"
                fi
                
                # Show appropriate dialog based on type
                case "$dialog_type" in
                    "fselect")
                        if user_input=$(dialog --fselect "$HOME/" 15 70 3>&1 1>&2 2>&3); then
                            # Remove trailing slash if it's a directory selection for file
                            user_input="${user_input%/}"
                        else
                            clear
                            printf "%s\n" "$(_ "Aborted.")"
                            printf "%s" "$(_ "Press enter to return...")"
                            read -r
                            return 1
                        fi
                        ;;
                    "dselect")
                        if user_input=$(dialog --dselect "$HOME/" 15 70 3>&1 1>&2 2>&3); then
                            # Ensure directory has trailing slash
                            [[ "$user_input" != */ ]] && user_input="${user_input}/"
                        else
                            clear
                            printf "%s\n" "$(_ "Aborted.")"
                            printf "%s" "$(_ "Press enter to return...")"
                            read -r
                            return 1
                        fi
                        ;;
                    "passwordbox")
                        if user_input=$(dialog --insecure --passwordbox "$(printf "$(_ "Please enter '%s':")" "$placeholder")" 10 60 3>&1 1>&2 2>&3); then
                            # Password input successful
                            :
                        else
                            clear
                            printf "%s\n" "$(_ "Aborted.")"
                            printf "%s" "$(_ "Press enter to return...")"
                            read -r
                            return 1
                        fi
                        ;;
                    *)
                        # Default inputbox for unrecognized placeholders
                        if user_input=$(dialog --inputbox "$(printf "$(_ "Please enter '%s':")" "$placeholder")" 10 60 3>&1 1>&2 2>&3); then
                            # Input successful
                            :
                        else
                            clear
                            printf "%s\n" "$(_ "Aborted.")"
                            printf "%s" "$(_ "Press enter to return...")"
                            read -r
                            return 1
                        fi
                        ;;
                esac
                
                # Replace placeholder with user input
                processed_args="${processed_args//<$placeholder>/$user_input}"
            done
            full_command="$cmd $processed_args"
        else
            # Use arguments directly
            full_command="$cmd $args"
        fi
    else
        full_command="$cmd"
    fi
    
    clear
    if [[ "$COMMAND_DEBUG" == "1" ]]; then
        printf "$(_ "Running: %s")\n" "$full_command"
        printf '%s\n' '----------------------------------------'
    fi
    
    # Use bash -c instead of eval for better safety
    if bash -c "$full_command"; then
        printf '%s\n' '----------------------------------------'
        printf "%s\n" "$(_ "Command executed successfully.")"
    else
        local exit_code=$?
        printf '%s\n' '----------------------------------------'
        printf "$(_ "Error while executing command (Exit Code: %d).")\n" "$exit_code"
    fi
    
    printf "\n"
    printf "%s" "$(_ "Press enter to return...")"
    read -r
}

# Show menu for a .txt file
run_textmenu() {
    local menufile="$1"
    
    if ! parse_menufile "$menufile"; then
        dialog --msgbox "$(printf "$(_ "Error loading file:\\n%s")" "$menufile")" 10 70
        clear
        return 1
    fi
    
    if [[ ${#PARSED[@]} -eq 0 ]]; then
        dialog --msgbox "$(printf "$(_ "No valid entries in:\\n%s")" "$menufile")" 10 70
        clear
        return 1
    fi

    while true; do
        local menu_entries=()
        local display_entries=()

        for ((i=0; i<${#PARSED[@]}; i+=4)); do
            menu_entries+=("${PARSED[$i]}" "${PARSED[$((i+1))]}" "${PARSED[$((i+2))]}" "${PARSED[$((i+3))]}")
            display_entries+=("${PARSED[$i]}" "${PARSED[$((i+1))]}")
        done

        clear
        local choice
        choice=$(dialog --begin 3 1 \
            --title "$(_ "List contents")" \
            --ok-label "$(_ "Select")" \
            --cancel-label "$(_ "Exit")" \
            --menu "$(_ "Please select an item and press enter to confirm, escape to exit ATMIRAL:")" 0 0 0 \
            "$(_ "...")" "$(_ "Parent level")" \
            "${display_entries[@]}" \
            3>&1 1>&2 2>&3)

        # Handle exit on escape
        local status=$?
        if [[ $status -ne 0 ]]; then
            exit 0
        fi

        # Back to parent menu
        if [[ "$choice" == "$(_ "...")" ]]; then
            return 0
        fi

        # Execute selected command
        for ((i=0; i<${#menu_entries[@]}; i+=4)); do
            if [[ "${menu_entries[$i]}" == "$choice" ]]; then
                clear
                execute_command "${menu_entries[$((i+2))]}" "${menu_entries[$((i+3))]}"
                break
            fi
        done
    done
}

# Folder menu
run_menu() {
    local current_dir="$1"
    
    if [[ ! -d "$current_dir" ]]; then
        printf "$(_ "Error: Menu directory '%s' doesn't exist.")\n" "$current_dir" >&2
        return 1
    fi

    while true; do
        local menu_entries=()
        local display_entries=()

        # Subfolders as categories
        for dir in "$current_dir"/*/; do
            [[ -d "$dir" ]] || continue
            local base
            base=$(basename "$dir")
            menu_entries+=("$base" "$(_ "Folder: ")$base" "submenu:$dir")
            display_entries+=("$base" "$(_ "Folder: ")$base")
        done

        # Every .txt file as own submenu
        for file in "$current_dir"/*.txt; do
            [[ -e "$file" ]] || continue
            local base
            base=$(basename "$file" .txt)
            menu_entries+=("$base" "$(_ "Programs from ")$base" "textmenu:$file")
            display_entries+=("$base" "$(_ "Programs from ")$base")
        done

        clear
        if [[ ${#display_entries[@]} -eq 0 ]]; then
            dialog --msgbox "$(printf "$(_ "No entries in directory:\\n%s")" "$current_dir")" 10 70
            clear
            return 0
        fi

        local choice
        choice=$(dialog --begin 3 1 \
            --title "$(_ "Folder list")" \
            --ok-label "$(_ "Select")" \
            --cancel-label "$(_ "Exit")" \
            --menu "$(_ "Please select an item and press enter to confirm, escape to exit ATMIRAL:")" 0 0 0 \
            "$(_ "...")" "$(_ "Parent level")" \
            "${display_entries[@]}" \
            3>&1 1>&2 2>&3)

        # Handle exit on escape
        local status=$?
        if [[ $status -ne 0 ]]; then
            exit 0
        fi

        # Back to parent menu
        if [[ "$choice" == "$(_ "...")" ]]; then
            return 0
        fi

        # Handle menu selection
        for ((i=0; i<${#menu_entries[@]}; i+=3)); do
            if [[ "${menu_entries[$i]}" == "$choice" ]]; then
                local action="${menu_entries[$((i+2))]}"

                if [[ "$action" == submenu:* ]]; then
                    run_menu "${action#submenu:}"
                elif [[ "$action" == textmenu:* ]]; then
                    run_textmenu "${action#textmenu:}"
                fi
                break
            fi
        done
    done
}

# Main execution
main() {
    
    if ! run_menu "$MENUDIR"; then
        printf "%s\n" "$(_ "Error while executing main menu.")" >&2
        exit 1
    fi
}

# Trap to handle cleanup on script exit
cleanup() {
    clear
    printf '%s\n' "$(_ "Exited ATMIRAL.")"
}
trap cleanup EXIT

# Start the application
main "$@"
