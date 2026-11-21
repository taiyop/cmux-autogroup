# cmux-autogroup

[日本語](README.ja.md)

Automatically organize [cmux](https://cmux.com/) workspaces into sidebar **Workspace Groups** by Git repository root whenever you open a workspace or `cd` into a repository.

## Features

- **Zero extra anchor tabs**: Creates each repository group using your current workspace (`--from "$CMUX_WORKSPACE_ID"`) instead of spawning an extra empty anchor workspace.
- **Seamless switching between repositories**: When moving out of a group whose **anchor** is the current workspace:
  - If other workspaces remain in that group, transfers anchor ownership via `cmux workspace-group set-anchor` so the old group stays intact.
  - If it was the only workspace in the group, dissolves the old group via `cmux workspace-group ungroup` without closing your workspace.
  - Pinned empty groups are protected and left untouched.
- **Idempotent & window-scoped**: Uses `--idempotency-key "repo:<canonical-path>"` and `--id-format both` so multiple workspaces in the same repo cleanly join the same group.
- **Lightweight**: Runs once on shell startup (self-removing `precmd` hook) and on directory changes (`chpwd`), caching `$PWD` so `git` is not invoked on every prompt.
- **No-op outside cmux**: Immediately exits when `CMUX_WORKSPACE_ID` is unset.

## Requirements

- [cmux](https://cmux.com/) with `workspace-group` CLI and `--id-format both` support (tested on `cmux 0.65.2`)
- `zsh`
- `git`
- `jq` (pre-installed on macOS 15+, or `brew install jq`)

## Installation

### Manual (`~/.zshrc`)

```zsh
git clone https://github.com/taiyop/cmux-autogroup.git ~/.config/cmux/cmux-autogroup
```

Add the following near the end of your `~/.zshrc` (after `PATH` setup):

```zsh
if [[ -n "${CMUX_WORKSPACE_ID:-}" && -r "$HOME/.config/cmux/cmux-autogroup/cmux-autogroup.plugin.zsh" ]]; then
  export CMUX_GROUP_BASE="$HOME/Projects"
  source "$HOME/.config/cmux/cmux-autogroup/cmux-autogroup.plugin.zsh"
fi
```

### Sheldon

```toml
[plugins.cmux-autogroup]
github = "taiyop/cmux-autogroup"
```

### zinit

```zsh
zinit light taiyop/cmux-autogroup
```

### antidote

```text
taiyop/cmux-autogroup
```

### Oh My Zsh

```zsh
git clone https://github.com/taiyop/cmux-autogroup.git \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/cmux-autogroup"
```

Then add `cmux-autogroup` to `plugins=(...)` in `~/.zshrc`.

## Configuration

Set these environment variables **before** sourcing `cmux-autogroup.plugin.zsh`:

| Variable | Default | Description |
| --- | --- | --- |
| `CMUX_GROUP_BASE` | `$HOME/Projects` | Target root folder(s) to auto-group. Supports colon-separated paths (e.g. `"$HOME/repos:$HOME/work"`). Set to `""` or `"*"` to match **all** Git repositories. |
| `CMUX_GROUP_WORKTREE_MODE` | `separate` | `separate`: one group per git worktree (`--show-toplevel`). `shared`: bundle worktrees into their main repository's group (`--git-common-dir`). |
| `CMUX_GROUP_NAME_MODE` | `basename` | `basename`: use the repository folder name (e.g. `app`). `relative`: use the path relative to the matched `CMUX_GROUP_BASE` (e.g. `team/app`) to disambiguate same-named repos. |
| `CMUX_AUTO_GROUP_DEBUG` | `0` | Set to `1` to print error/skip diagnostics to `stderr`. |

## Usage & Tips

- **New Workspace (`⌘N`)**: With cmux's default `workspaceInheritWorkingDirectory: true`, pressing `⌘N` inside a repository opens a new workspace in the same directory and automatically places it into the same repository group.
- **Force re-sync**: Run `cmux-autogroup-sync` (or `CMUX_AUTO_GROUP_DEBUG=1 cmux-autogroup-sync`) to re-evaluate the current directory manually.
- **Multi-pane workspaces**: `CMUX_WORKSPACE_ID` is shared across panes/tabs in the same workspace, so `cd`ing to a different repo in another pane will move the entire workspace to that repo's group.
- **Multiple windows (`⌘⇧N`)**: cmux workspace groups are window-scoped, so each cmux window maintains its own groups.

## Development & Tests

Run the mock-based test suite (no running cmux instance required):

```zsh
zsh tests/test_autogroup.zsh
```

## License

[MIT](LICENSE)
