# nadm

**Not A Dotfile Manager** — bootstrap [jj](https://github.com/martinvonz/jj) as a dotfile manager.

nadm turns your home directory into a jj repository with a non-colocated git backend. You selectively track dotfiles with `jj dot add`, and nadm maintains the `.gitignore` so jj only sees what you've opted in.

## Quick start

Requires [jj](https://github.com/martinvonz/jj) to be installed.

### New setup

```sh
npx nadm init
jj dot add ~/.config/nvim
jj dot add ~/.zshrc
jj commit -m "add dotfiles"
```

### Clone existing dotfiles

```sh
npx nadm clone https://github.com/you/dotfiles.git
# or
npx nadm clone --github you/dotfiles
```

## Usage

After initialization, nadm adds a `jj dot` alias with the following subcommands:

| Command | Description |
|---|---|
| `jj dot add <path>...` | Track a file or directory |
| `jj dot forget <path>...` | Stop tracking a file or directory |
| `jj dot sync` | Regenerate `.gitignore` from the tracked list |
| `jj dot edit` | Open `~/.nadm/tracked` in `$EDITOR`, then sync |

Paths can be absolute or relative. Directories are tracked recursively.

## How it works

1. `npx nadm init` creates a jj repo in `~` with `jj git init --no-colocate`
2. A `~/.nadm/` directory holds the tracked file list, the `dot.sh` script, and a `config.toml` that registers the `jj dot` alias
3. `~/.gitignore` starts by ignoring everything (`*`), then selectively unignores tracked paths and their parent directories
4. When you `jj dot add` a path, it's appended to `~/.nadm/tracked` and the gitignore is regenerated

Since jj uses a git backend, you can push your dotfiles to any git remote:

```sh
jj git remote add origin https://github.com/you/dotfiles.git
jj git push
```

## File layout

After running `nadm init`, the following is created in your home directory:

```
~/
  .jj/                   # jj repository (non-colocated git backend)
  .nadm/
    tracked              # plain text list of tracked paths
    dot.sh               # jj dot subcommand implementation
    config.toml          # jj config with the dot alias
  .gitignore             # auto-generated, do not edit directly
```

## License

MIT
