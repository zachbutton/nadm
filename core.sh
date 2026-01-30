#!/usr/bin/env bash
set -e

# Colors
BOLD='\033[1m'
CYAN='\033[36m'
DIM='\033[2m'
RED='\033[31m'
RESET='\033[0m'

# Print error and exit
error() {
    echo -e "${RED}Error:${RESET} $1" >&2
    exit 1
}

# Arrow-key menu
# Usage: menu_select "Title" "option1" "option2" ...
# Returns: selected index (0-based) in $MENU_RESULT
menu_select() {
    local title="$1"
    shift
    local options=("$@")
    local selected=0
    local count=${#options[@]}

    # Hide cursor
    printf '\033[?25l'

    # Cleanup on exit
    trap 'printf "\033[?25h"' EXIT

    # Print title
    echo -e "${BOLD}${title}${RESET}"
    echo

    # Draw menu
    draw_menu() {
        for i in "${!options[@]}"; do
            # Move to start of line, clear it
            printf '\r\033[K'
            if [[ $i -eq $selected ]]; then
                echo -e "${CYAN}❯ ${options[$i]}${RESET}"
            else
                echo -e "${DIM}  ${options[$i]}${RESET}"
            fi
        done
    }

    draw_menu

    # Read input
    while true; do
        # Read single character
        IFS= read -rsn1 key

        case "$key" in
            # Arrow keys start with escape
            $'\x1b')
                read -rsn2 -t 0.1 rest
                case "$rest" in
                    '[A') # Up arrow
                        ((selected = selected > 0 ? selected - 1 : count - 1))
                        ;;
                    '[B') # Down arrow
                        ((selected = selected < count - 1 ? selected + 1 : 0))
                        ;;
                esac
                ;;
            # Vim keys
            'k')
                ((selected = selected > 0 ? selected - 1 : count - 1))
                ;;
            'j')
                ((selected = selected < count - 1 ? selected + 1 : 0))
                ;;
            # Ctrl+P (up)
            $'\x10')
                ((selected = selected > 0 ? selected - 1 : count - 1))
                ;;
            # Ctrl+N (down)
            $'\x0e')
                ((selected = selected < count - 1 ? selected + 1 : 0))
                ;;
            # Enter or Ctrl+M
            ''|$'\x0d')
                break
                ;;
            # q or Ctrl+C
            'q'|$'\x03')
                printf '\033[?25h'
                exit 0
                ;;
        esac

        # Move cursor up to redraw
        printf "\033[${count}A"
        draw_menu
    done

    # Show cursor
    printf '\033[?25h'
    echo

    MENU_RESULT=$selected
}
