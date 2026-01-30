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

    # Validate we have at least one option
    [[ $count -eq 0 ]] && error "menu_select requires at least one option"

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

# Shared setup (used by both init and clone)
do_setup() {
    cd "$HOME"

    # Guards
    [[ -d ".jj" ]] && error "Already initialized. Remove ~/.jj to re-initialize."
    [[ -f ".gitignore" ]] && error "~/.gitignore already exists."

    # Check jj is installed
    command -v jj >/dev/null 2>&1 || error "jj is not installed. See https://github.com/martinvonz/jj"

    # Create .gitignore with * (ignore everything)
    echo '*' > .gitignore

    # Initialize jj repo
    jj git init --no-colocate

    # Create .nadm directory
    mkdir -p .nadm

    # Create config with add alias
    cat > .nadm/config.toml << 'EOF'
[aliases]
add = ["file", "track", "--include-ignored"]
EOF

    # Remove auto-generated config if it exists
    rm -f .jj/repo/config.toml

    # Symlink config
    ln -s "$HOME/.nadm/config.toml" .jj/repo/config.toml

    # Track our files
    jj add .gitignore
    jj add .nadm/config.toml
}

cmd_init() {
    echo -e "${BOLD}Initializing nadm...${RESET}"
    do_setup
    echo -e "${CYAN}Done!${RESET} Your home directory is now a jj repo."
    echo "Use 'jj add <file>' to start tracking dotfiles."
}
