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

cmd_clone() {
    local url="$1"

    [[ -z "$url" ]] && error "Usage: nadm clone <url>"

    echo -e "${BOLD}Cloning dotfiles...${RESET}"

    # Run shared setup first
    do_setup

    # Add remote and fetch
    cd "$HOME"
    jj git remote add origin "$url" || error "Failed to add remote. Check the URL."
    jj git fetch || error "Failed to fetch from remote. Check your network/credentials."

    # Get bookmarks
    local bookmarks
    bookmarks=$(jj bookmark list -a 2>/dev/null) || true

    [[ -z "$bookmarks" ]] && error "No bookmarks found on remote."

    # Count bookmarks
    local count
    count=$(echo "$bookmarks" | wc -l | tr -d ' ')

    local bookmark_name
    if [[ "$count" -eq 1 ]]; then
        # Single bookmark - use it directly
        bookmark_name=$(echo "$bookmarks" | awk '{print $1}' | sed 's/:$//')
    else
        # Multiple bookmarks - show menu
        echo
        echo "Multiple bookmarks found. Select one:"
        echo

        # Convert bookmarks to array
        local -a bookmark_lines
        while IFS= read -r line; do
            bookmark_lines+=("$line")
        done <<< "$bookmarks"

        menu_select "Select bookmark:" "${bookmark_lines[@]}"

        # Extract bookmark name from selected line
        bookmark_name=$(echo "${bookmark_lines[$MENU_RESULT]}" | awk '{print $1}' | sed 's/:$//')
    fi

    # Create new working copy on selected bookmark
    jj new "$bookmark_name" || error "Failed to create working copy on '${bookmark_name}'."

    echo -e "${CYAN}Done!${RESET} Dotfiles cloned from ${url}"
    echo "Your working copy is now on top of '${bookmark_name}'."
}

show_main_menu() {
    menu_select "nadm - Not A Dotfile Manager" \
        "init   Create a fresh dotfile repo" \
        "clone  Set up from an existing remote"

    case $MENU_RESULT in
        0) cmd_init ;;
        1)
            echo -n "Enter remote URL: "
            read -r url
            cmd_clone "$url"
            ;;
    esac
}

main() {
    # Parse args from NADM_ARGS env var (set by wrappers)
    local args="${NADM_ARGS:-}"

    # Also accept direct args for testing
    [[ -n "$1" ]] && args="$*"

    # Parse command
    local cmd="${args%% *}"
    local rest="${args#* }"
    [[ "$cmd" == "$rest" ]] && rest=""

    case "$cmd" in
        init)
            cmd_init
            ;;
        clone)
            cmd_clone "$rest"
            ;;
        ""|help|--help|-h)
            if [[ -t 0 && -t 1 ]]; then
                # Interactive terminal - show menu
                show_main_menu
            else
                # Non-interactive - show usage
                echo "Usage: nadm <command>"
                echo ""
                echo "Commands:"
                echo "  init          Create a fresh dotfile repo in ~"
                echo "  clone <url>   Set up from an existing remote"
            fi
            ;;
        *)
            error "Unknown command: $cmd"
            ;;
    esac
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
