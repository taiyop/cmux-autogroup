# cmux-autogroup

[日本語](README.ja.md)

Automatically organize [cmux](https://cmux.com/) workspaces into sidebar **Workspace Groups** by Git repository root whenever you open a workspace or `cd` into a repository.

Supports **Zsh**, **Bash**, and **Fish** via a shared core (`bin/cmux-autogroup`) and thin shell wrappers.

## Features

- **Multi-shell support**: Works in Zsh, Bash (3.2+), and Fish with a single shared core and lightweight shell hooks.
- **Zero extra anchor tabs**: Creates each repository group using your current workspace (`--from "$CMUX_WORKSPACE_ID"`) instead of spawning an extra empty anchor workspace.
- **Seamless switching between repositories**: When moving out of a group whose **anchor** is the current workspace:
  - If other workspaces remain in that group, transfers anchor ownership via `cmux workspace-group set-anchor` so the old group stays intact.
  - If it was the only workspace in the group, dissolves the old group via `cmux workspace-group ungroup` without closing your workspace.
  - Pinned empty groups are protected and left untouched.
- **Idempotent & window-scoped**: Uses `--idempotency-key "repo:<canonical-path>"` and `--id-format both` so multiple workspaces in the same repo cleanly join the same group.
- **Lightweight**: Each shell wrapper caches `$PWD` in-process, so no subprocess is spawned on prompts when your directory has not changed.
- **No-op outside cmux**: Immediately exits when `CMUX_WORKSPACE_ID` is unset.

## Requirements

- [cmux](https://cmux.com/) with `workspace-group` CLI and `--id-format both` support (tested on `cmux 0.65.2`)
- `bash` (3.2+, pre-installed on macOS/Linux) for the shared core
- `git`
- `jq` (pre-installed on macOS 15+, or `brew install jq`)

## Installation

First, clone the repository:

```sh
git clone https://github.com/taiyop/cmux-autogroup.git ~/.config/cmux/cmux-autogroup
```

### Zsh

Add near the end of `~/.zshrc` (after `PATH` setup):

```zsh
if [[ -n "${CMUX_WORKSPACE_ID:-}" && -r "$HOME/.config/cmux/cmux-autogroup/cmux-autogroup.plugin.zsh" ]]; then
  export CMUX_GROUP_BASE="$HOME/Projects"
  source "$HOME/.config/cmux/cmux-autogroup/cmux-autogroup.plugin.zsh"
fi
```

Or use your Zsh plugin manager:
- **Sheldon**:
  ```toml
  [plugins.cmux-autogroup]
  github = "taiyop/cmux-autogroup"
  ```
- **zinit**: `zinit light taiyop/cmux-autogroup`
- **antidote**: `taiyop/cmux-autogroup`
- **Oh My Zsh**: clone into `${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/cmux-autogroup` and add `cmux-autogroup` to `plugins=(...)`

### Bash

Add near the end of `~/.bashrc` (or `~/.bash_profile`):

```bash
if [[ -n "${CMUX_WORKSPACE_ID:-}" && -r "$HOME/.config/cmux/cmux-autogroup/init/cmux-autogroup.bash" ]]; then
  export CMUX_GROUP_BASE="$HOME/Projects"
  source "$HOME/.config/cmux/cmux-autogroup/init/cmux-autogroup.bash"
fi
```

### Fish

Add to `~/.config/fish/config.fish`:

```fish
if set -q CMUX_WORKSPACE_ID; and test -r "$HOME/.config/cmux/cmux-autogroup/init/cmux-autogroup.fish"
    set -gx CMUX_GROUP_BASE "$HOME/Projects"
    source "$HOME/.config/cmux/cmux-autogroup/init/cmux-autogroup.fish"
end
```

## Configuration

Set these environment variables **before** sourcing the hook:

| Variable | Default | Description |
| --- | --- | --- |
| `CMUX_GROUP_BASE` | `$HOME/Projects` | Target root folder(s) to auto-group. Supports colon-separated paths (e.g. `"$HOME/repos:$HOME/work"`). Set to `""` or `"*"` to match **all** Git repositories. |
| `CMUX_GROUP_WORKTREE_MODE` | `separate` | `separate`: one group per git worktree (`--show-toplevel`). `shared`: bundle worktrees into their main repository's group (`--git-common-dir`). |
| `CMUX_GROUP_NAME_MODE` | `basename` | `basename`: use the repository folder name (e.g. `app`). `relative`: use the path relative to the matched `CMUX_GROUP_BASE` (e.g. `team/app`) to disambiguate same-named repos. |
| `CMUX_AUTO_GROUP_DEBUG` | `0` | Set to `1` to print error/skip diagnostics to `stderr`. |

## Architecture

```text
cmux-autogroup/
├── bin/cmux-autogroup          # Shared core (Bash 3.2+ compatible)
├── cmux-autogroup.plugin.zsh   # Zsh wrapper (chpwd + one-shot precmd)
├── init/cmux-autogroup.bash    # Bash wrapper (PROMPT_COMMAND)
├── init/cmux-autogroup.fish    # Fish wrapper (--on-variable PWD)
└── tests/run_tests.bash        # Mock-based core + shell wrapper test suite
```

## Usage & Tips

- **New Workspace (`⌘N`)**: With cmux's default `workspaceInheritWorkingDirectory: true`, pressing `⌘N` inside a repository opens a new workspace in the same directory and automatically places it into the same repository group.
- **Force re-sync**: Run `cmux-autogroup-sync` (or `CMUX_AUTO_GROUP_DEBUG=1 cmux-autogroup-sync`) to re-evaluate the current directory manually.
- **Multi-pane workspaces**: `CMUX_WORKSPACE_ID` is shared across panes/tabs in the same workspace, so `cd`ing to a different repo in another pane will move the entire workspace to that repo's group.
- **Multiple windows (`⌘⇧N`)**: cmux workspace groups are window-scoped, so each cmux window maintains its own groups.

## Development & Tests

Run the mock-based test suite (no running cmux instance required):

```sh
bash tests/run_tests.bash
```

## License

[MIT](LICENSE)
