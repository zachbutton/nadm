# nadm Design Document

**Date:** 2026-01-30

## Overview

nadm (Not A Dotfile Manager) is a minimal CLI that bootstraps jj as a dotfile manager. It leverages jj's native capabilities - the insight being that jj already handles the hard parts of dotfile management (tracking specific files in an otherwise-ignored directory, syncing with remotes).

## Commands

- `nadm` (no args) - interactive menu to choose init or clone
- `nadm init` - create fresh dotfile repo in `~`
- `nadm clone <url>` - set up from existing remote

## Architecture

Monorepo with shared bash core and thin wrappers:

```
nadm/
├── core.sh              # All logic lives here
├── package.json         # npm package definition
├── bin/nadm.js          # Node wrapper (embeds core.sh)
├── go.mod               # Go module definition
├── main.go              # Go wrapper (go:embed core.sh)
└── README.md
```

**Distribution:**
- `npx nadm` - Node users
- `go run github.com/user/nadm@latest` - Go users

The bash script is embedded at build time into each wrapper, so there's no runtime network dependency and a single source of truth for the logic.

## Init Flow

When `nadm init` runs:

**Guards (fail fast):**
1. Check if `~/.jj` exists → error: "Already initialized"
2. Check if `~/.gitignore` exists → error: ".gitignore already exists"

**Setup:**
3. Create `~/.gitignore` containing just `*` (ignore everything by default)
4. Run `jj git init --no-colocate` in `~`
5. Create `~/.nadm/` directory
6. Create `~/.nadm/config.toml` with:
   ```toml
   [aliases]
   add = ["file", "track", "--include-ignored"]
   ```
7. Remove the auto-generated `~/.jj/repo/config.toml` (if it exists)
8. Create symlink: `~/.jj/repo/config.toml` → `~/.nadm/config.toml`
9. Run `jj add .gitignore` (using our new alias)
10. Run `jj add .nadm/config.toml`

**Result:** User has a jj repo in their home directory where everything is ignored by default. They can now `jj add ~/.bashrc` (or any dotfile) to start tracking it.

## Clone Flow

When `nadm clone <url>` runs:

**Guards (same as init):**
1. Check if `~/.jj` exists → error: "Already initialized"
2. Check if `~/.gitignore` exists → error: ".gitignore already exists"

**Setup (same as init):**
3. Create `~/.gitignore` with `*`
4. Run `jj git init --no-colocate`
5. Create `~/.nadm/config.toml` with the `add` alias
6. Symlink `~/.jj/repo/config.toml` → `~/.nadm/config.toml`
7. Run `jj add .gitignore`
8. Run `jj add .nadm/config.toml`

**Remote sync (clone-specific):**
9. Run `jj git remote add origin <url>`
10. Run `jj git fetch`
11. Run `jj bookmark list -a`, capture output
12. If one bookmark → extract bookmark name, run `jj new <bookmark>`
13. If multiple bookmarks → display raw jj output as arrow-key menu items, user selects, extract bookmark name from chosen line, run `jj new <bookmark>`

**Result:** User's dotfiles from the remote are now in their home directory, with a fresh working copy change on top of the chosen bookmark.

## Interactive Menu UX

The arrow-key menu is used in two places:
1. Main menu (no args) - choose between init and clone
2. Bookmark selection (clone with multiple bookmarks)

**Behavior:**
- Display options with one highlighted (first by default)
- `↑`/`k`/`Ctrl+P` moves highlight up
- `↓`/`j`/`Ctrl+N` moves highlight down
- `Enter`/`Ctrl+M` selects the highlighted option
- `q`/`Ctrl+C` exits

**Main menu appearance:**
```
nadm - Not A Dotfile Manager

❯ init   Create a fresh dotfile repo
  clone  Set up from an existing remote
```

**Implementation approach (pure bash):**
- Use ANSI escape codes for colors and cursor movement
- Read single characters with `read -rsn1`
- Detect arrow keys (escape sequences: `\e[A` for up, `\e[B` for down)
- Redraw menu on each keypress using `\e[<n>A` to move cursor up
- Highlight current selection with color (e.g., cyan) and `❯` prefix

**Colors:**
- Title: bold
- Selected item: cyan with `❯` prefix
- Unselected items: dim/gray with space prefix

## Wrapper Implementations

**Node wrapper (`bin/nadm.js`):**
```javascript
#!/usr/bin/env node
const { execSync } = require('child_process');
const script = `... embedded core.sh contents ...`;

execSync(`bash -c ${JSON.stringify(script)}`, {
  stdio: 'inherit',
  env: { ...process.env, NADM_ARGS: process.argv.slice(2).join(' ') }
});
```

Build step in `package.json` replaces the placeholder with actual `core.sh` contents before publish.

**Go wrapper (`main.go`):**
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
    cmd.Run()
}
```

**Argument passing:** Both wrappers pass CLI args via `NADM_ARGS` environment variable. `core.sh` parses this at the top.

## Error Handling

**Prerequisite checks:**
- `jj` not installed → "Error: jj is not installed. See https://github.com/martinvonz/jj"
- `~/.jj` exists → "Error: Already initialized. Remove ~/.jj to re-initialize."
- `~/.gitignore` exists → "Error: ~/.gitignore already exists."

**Clone-specific errors:**
- No URL provided → "Usage: nadm clone <url>"
- `jj git remote add` fails → "Error: Failed to add remote. Check the URL."
- `jj git fetch` fails → "Error: Failed to fetch from remote. Check your network/credentials."
- No bookmarks after fetch → "Error: No bookmarks found on remote."

**General approach:**
- Use `set -e` in bash to exit on any command failure
- Wrap critical commands with descriptive error messages
- Always exit with non-zero status on error
- Keep error messages short and actionable

**Colors for errors:**
- Error prefix in red: `Error:`
- Suggestion/help text in normal color

## Summary

| Aspect | Decision |
|--------|----------|
| Architecture | Monorepo: `core.sh` + Node/Go wrappers |
| Commands | `nadm`, `nadm init`, `nadm clone <url>` |
| Target directory | Always `~` |
| Menu UX | Arrow-key navigation (pure bash) |
| Keybindings | `↑`/`k`/`Ctrl+P` up, `↓`/`j`/`Ctrl+N` down, `Enter`/`Ctrl+M` select |
| Bookmark selection | Raw jj output as menu items |
| Error handling | Fail fast with clear messages |
| Config location | `~/.nadm/config.toml` symlinked from `~/.jj/repo/config.toml` |

## Files to Create

- `core.sh` - ~150-200 lines of bash
- `bin/nadm.js` - ~15 lines
- `main.go` - ~20 lines
- `go.mod` - module definition
- `package.json` - update with bin entry and build script
