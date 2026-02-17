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

# Shared setup (used by both init and clone)
do_setup() {
    cd "$HOME"

    # Guards
    [[ -d ".jj" ]] && error "Already initialized. Remove ~/.jj to re-initialize."

    # Check jj is installed
    command -v jj >/dev/null 2>&1 || error "jj is not installed. See https://github.com/martinvonz/jj"

    # Initialize jj repo
    jj git init --no-colocate

    # Create .nadm directory
    [[ -d ".nadm" ]] || mkdir -p .nadm

    # Create config with add/sync aliases
    cat > .nadm/config.toml << 'EOF'
[aliases]
add = ["util", "exec", "--", "bash", "-c", """
#!/usr/bin/env bash
printf '%s\n' "$@" >> .nadm/tracked
jj sync
""", ""]
sync = ["util", "exec", "--", "bash", "-c", """
#!/usr/bin/env bash
if [[ ! -f .nadm/tracked ]]; then
    exit 0
fi

jj sparse set --clear
jj sparse set --add .nadm/
while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    jj sparse set --add "$path"
done < .nadm/tracked
""", ""]
EOF

    # Remove auto-generated config if it exists
    rm -f .jj/repo/config.toml

    # Symlink config
    ln -s "$HOME/.nadm/config.toml" .jj/repo/config.toml

	echo '*' > .gitignore
	jj sparse set --clear
	rm .gitignore

    jj add .nadm
}

show_usage() {
    echo "Usage: nadm <command>"
    echo ""
    echo "Commands:"
    echo "  init"
    echo "  clone <url>"
    echo "  clone --github <owner/repo>"
}

cmd_init() {
    echo -e "${BOLD}Initializing nadm...${RESET}"

	do_setup

    echo
    echo -e "${CYAN}Done!${RESET} Your home directory is now a jj repo."
    echo "Use 'jj add <file>' to start tracking dotfiles."
    echo
    jj status
}

cmd_clone() {
    local url="$1"

    [[ -z "$url" ]] && error "Usage: nadm clone <url>"

    echo -e "${BOLD}Cloning dotfiles...${RESET}"

	do_setup
	jj git remote add origin $url
	jj git fetch

    echo
    echo -e "${CYAN}Done!${RESET} Your home directory is now a jj repo."
    echo "Use 'jj add <file>' to start tracking dotfiles."
    echo
    jj status
}

main() {
    local -a args=()

    if [[ $# -gt 0 ]]; then
        args=("$@")
    elif [[ -n "${NADM_ARGS:-}" ]]; then
        read -r -a args <<< "${NADM_ARGS}"
    fi

    local cmd="${args[0]:-}"

    case "$cmd" in
        init)
            cmd_init
            ;;
        clone)
            if [[ "${args[1]:-}" == "--github" ]]; then
                local repo="${args[2]:-}"
                [[ -z "$repo" ]] && error "Usage: nadm clone --github <owner/repo>"
                cmd_clone "https://github.com/${repo}.git"
            else
                cmd_clone "${args[1]:-}"
            fi
            ;;
        ""|help|--help|-h)
            show_usage
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
