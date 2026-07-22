#!/bin/bash
# Shared GNU gettext setup for ATMIRAL.
ATMIRAL_TEXTDOMAIN="atmiral"

atmiral_init_i18n() {
    local script_dir="$1"
    local configured_language="${2:-}"
    export TEXTDOMAIN="$ATMIRAL_TEXTDOMAIN"
    if [[ "$script_dir" == /usr/local/bin ]]; then
        export TEXTDOMAINDIR="/usr/local/share/locale"
    elif [[ "$script_dir" == "$HOME/.local/bin" ]]; then
        export TEXTDOMAINDIR="$HOME/.local/share/locale"
    else
        export TEXTDOMAINDIR="$script_dir/locale"
    fi
    if [[ -n "$configured_language" ]]; then export LANGUAGE="$configured_language"; fi
}

_() { gettext -- "$1"; }
