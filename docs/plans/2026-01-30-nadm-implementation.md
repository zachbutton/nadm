# nadm Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a minimal CLI that bootstraps jj as a dotfile manager, distributable via npm and Go.

**Architecture:** Monorepo with `core.sh` containing all logic, thin Node and Go wrappers that embed the script at build time. Arrow-key menu UI in pure bash.

**Tech Stack:** Bash (core logic), Node.js (npm wrapper), Go (go run wrapper)

---

## Task 1: Arrow-Key Menu Function

**Files:**
- Create: `core.sh`

**Step 1: Create core.sh with menu function**

Create the reusable arrow-key menu function that will be used for both the main menu and bookmark selection.

```bash
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
```

**Step 2: Test the menu function manually**

Run: `bash -c 'source core.sh; menu_select "Test Menu" "Option A" "Option B" "Option C"; echo "Selected: $MENU_RESULT"'`

Expected: Interactive menu appears, arrow keys navigate, Enter selects, prints selected index.

**Step 3: Commit**

```bash
jj commit -m "feat: add arrow-key menu function"
```

---

## Task 2: Init Command

**Files:**
- Modify: `core.sh`

**Step 1: Add init function**

Append to `core.sh`:

```bash
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
```

**Step 2: Test init in a temp directory**

Run:
```bash
export HOME=$(mktemp -d)
bash -c 'source core.sh; cmd_init'
ls -la "$HOME"
ls -la "$HOME/.jj"
ls -la "$HOME/.nadm"
cat "$HOME/.nadm/config.toml"
readlink "$HOME/.jj/repo/config.toml"
```

Expected:
- `.gitignore` contains `*`
- `.jj/` directory exists
- `.nadm/config.toml` exists with alias
- `.jj/repo/config.toml` is symlink to `~/.nadm/config.toml`

**Step 3: Commit**

```bash
jj commit -m "feat: add init command"
```

---

## Task 3: Clone Command

**Files:**
- Modify: `core.sh`

**Step 1: Add clone function**

Append to `core.sh`:

```bash
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
    jj new "$bookmark_name"

    echo -e "${CYAN}Done!${RESET} Dotfiles cloned from ${url}"
    echo "Your working copy is now on top of '${bookmark_name}'."
}
```

**Step 2: Manual test** (requires a real remote with dotfiles)

This will be tested manually against a real dotfiles repo.

**Step 3: Commit**

```bash
jj commit -m "feat: add clone command"
```

---

## Task 4: Main Entry Point and Argument Parsing

**Files:**
- Modify: `core.sh`

**Step 1: Add main entry point**

Append to `core.sh`:

```bash
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
```

**Step 2: Test argument parsing**

Run:
```bash
chmod +x core.sh
./core.sh help
./core.sh --help
NADM_ARGS="help" ./core.sh
```

Expected: Shows usage text in all cases.

**Step 3: Commit**

```bash
jj commit -m "feat: add main entry point and argument parsing"
```

---

## Task 5: Node Wrapper

**Files:**
- Create: `bin/nadm.js`
- Modify: `package.json`

**Step 1: Create bin directory and wrapper**

```bash
mkdir -p bin
```

Create `bin/nadm.js`:

```javascript
#!/usr/bin/env node
const { spawnSync } = require('child_process');
const { readFileSync } = require('fs');
const { join } = require('path');

// In dev: read from file. In production: this gets replaced with embedded script.
let script;
try {
    // Try embedded script marker first (replaced during build)
    script = '{{CORE_SH}}';
    if (script === '{{' + 'CORE_SH}}') {
        // Not replaced - dev mode, read from file
        script = readFileSync(join(__dirname, '..', 'core.sh'), 'utf8');
    }
} catch (e) {
    console.error('Error: Could not load core.sh');
    process.exit(1);
}

const result = spawnSync('bash', ['-c', script], {
    stdio: 'inherit',
    env: {
        ...process.env,
        NADM_ARGS: process.argv.slice(2).join(' ')
    }
});

process.exit(result.status || 0);
```

**Step 2: Update package.json**

```json
{
  "name": "nadm",
  "version": "1.0.0",
  "description": "Not A Dotfile Manager - bootstrap jj as a dotfile manager",
  "main": "bin/nadm.js",
  "bin": {
    "nadm": "./bin/nadm.js"
  },
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1",
    "build": "node scripts/build.js",
    "prepublishOnly": "npm run build"
  },
  "keywords": ["dotfiles", "jj", "jujutsu"],
  "author": "",
  "license": "ISC"
}
```

**Step 3: Test Node wrapper locally**

Run:
```bash
chmod +x bin/nadm.js
node bin/nadm.js --help
```

Expected: Shows usage text.

**Step 4: Commit**

```bash
jj commit -m "feat: add Node.js wrapper"
```

---

## Task 6: Node Build Script

**Files:**
- Create: `scripts/build.js`

**Step 1: Create build script**

```bash
mkdir -p scripts
```

Create `scripts/build.js`:

```javascript
const { readFileSync, writeFileSync } = require('fs');
const { join } = require('path');

const coreSh = readFileSync(join(__dirname, '..', 'core.sh'), 'utf8');
const wrapperPath = join(__dirname, '..', 'bin', 'nadm.js');
let wrapper = readFileSync(wrapperPath, 'utf8');

// Escape for JavaScript string
const escaped = coreSh
    .replace(/\\/g, '\\\\')
    .replace(/`/g, '\\`')
    .replace(/\$/g, '\\$');

wrapper = wrapper.replace("'{{CORE_SH}}'", '`' + escaped + '`');

writeFileSync(wrapperPath, wrapper);
console.log('Build complete: core.sh embedded into bin/nadm.js');
```

**Step 2: Test build**

Run:
```bash
# Make a backup first
cp bin/nadm.js bin/nadm.js.bak
npm run build
node bin/nadm.js --help
# Restore
mv bin/nadm.js.bak bin/nadm.js
```

Expected: Build succeeds, wrapper still works.

**Step 3: Commit**

```bash
jj commit -m "feat: add Node build script for embedding core.sh"
```

---

## Task 7: Go Wrapper

**Files:**
- Create: `go.mod`
- Create: `main.go`

**Step 1: Create go.mod**

```
module github.com/zacharybutton/nadm

go 1.21
```

**Step 2: Create main.go**

```go
package main

import (
	_ "embed"
	"os"
	"os/exec"
	"strings"
)

//go:embed core.sh
var script string

func main() {
	cmd := exec.Command("bash", "-c", script)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(os.Environ(), "NADM_ARGS="+strings.Join(os.Args[1:], " "))

	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			os.Exit(exitErr.ExitCode())
		}
		os.Exit(1)
	}
}
```

**Step 3: Test Go wrapper**

Run:
```bash
go run . --help
```

Expected: Shows usage text.

**Step 4: Commit**

```bash
jj commit -m "feat: add Go wrapper"
```

---

## Task 8: Final Integration Test

**Files:** None (testing only)

**Step 1: Test Node wrapper end-to-end**

Run in a clean temp directory:
```bash
export HOME=$(mktemp -d)
node bin/nadm.js init
ls -la "$HOME/.jj"
ls -la "$HOME/.nadm"
cat "$HOME/.gitignore"
```

Expected: Full init completes successfully.

**Step 2: Test Go wrapper end-to-end**

Run in a clean temp directory:
```bash
export HOME=$(mktemp -d)
go run . init
ls -la "$HOME/.jj"
ls -la "$HOME/.nadm"
cat "$HOME/.gitignore"
```

Expected: Full init completes successfully.

**Step 3: Test interactive menu**

Run:
```bash
export HOME=$(mktemp -d)
./core.sh
```

Expected: Arrow-key menu appears, can navigate and select.

**Step 4: Commit any fixes**

If any issues found, fix and commit.

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Arrow-key menu function | `core.sh` |
| 2 | Init command | `core.sh` |
| 3 | Clone command | `core.sh` |
| 4 | Main entry point | `core.sh` |
| 5 | Node wrapper | `bin/nadm.js`, `package.json` |
| 6 | Node build script | `scripts/build.js` |
| 7 | Go wrapper | `go.mod`, `main.go` |
| 8 | Integration testing | - |
