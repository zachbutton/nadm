#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT_DIR/core.sh"

run_test() {
    local name="$1"
    shift

    if "$@"; then
        printf 'PASS %s\n' "$name"
    else
        printf 'FAIL %s\n' "$name"
        exit 1
    fi
}

assert_eq() {
    local expected="$1"
    local actual="$2"

    [[ "$expected" == "$actual" ]]
}

captured_action=""
captured_arg=""
captured_error=""

reset_captures() {
    captured_action=""
    captured_arg=""
    captured_error=""
}

cmd_init() {
    captured_action="init"
}

cmd_clone() {
    captured_action="clone"
    captured_arg="${1:-}"
}

error() {
    captured_error="$1"
    return 1
}

test_init_dispatch() {
    reset_captures
    main init
    assert_eq "init" "$captured_action"
}

test_clone_dispatch_url() {
    reset_captures
    main clone https://example.com/repo.git
    assert_eq "clone" "$captured_action" && assert_eq "https://example.com/repo.git" "$captured_arg"
}

test_clone_dispatch_github_shorthand() {
    reset_captures
    main clone --github owner/repo
    assert_eq "clone" "$captured_action" && assert_eq "https://github.com/owner/repo.git" "$captured_arg"
}

test_setup_writes_add_and_sync_aliases() {
    local temp_dir
    temp_dir="$(mktemp -d)"

    local old_home="$HOME"
    local old_path="$PATH"

    HOME="$temp_dir/home"
    mkdir -p "$HOME"

    mkdir -p "$temp_dir/bin"
    cat > "$temp_dir/bin/jj" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == "git" && "$2" == "init" ]]; then
    mkdir -p "$HOME/.jj/repo"
    exit 0
fi

if [[ "$1" == "add" ]]; then
    exit 0
fi

exit 0
EOF
    chmod +x "$temp_dir/bin/jj"
    PATH="$temp_dir/bin:$PATH"

    do_setup

    local config_file="$HOME/.nadm/config.toml"
    [[ -f "$config_file" ]] || return 1

    grep -F "printf '%s\\n' \"\$@\" >> .nadm/tracked" "$config_file" >/dev/null
    grep -F "while IFS= read -r path; do" "$config_file" >/dev/null
    grep -F "jj sparse set --add \"\$path\"" "$config_file" >/dev/null

    HOME="$old_home"
    PATH="$old_path"
    rm -rf "$temp_dir"
}

run_test "dispatches init" test_init_dispatch
run_test "dispatches clone URL" test_clone_dispatch_url
run_test "dispatches clone github shorthand" test_clone_dispatch_github_shorthand
run_test "setup writes add/sync aliases" test_setup_writes_add_and_sync_aliases
