# cmux-autogroup

[English](README.md)

[cmux](https://cmux.com/) で Git リポジトリのルート単位に **Workspace Group** を自動で作成・切り替えするツールです。  
共通コア（`bin/cmux-autogroup`）と薄いシェルラッパーにより、**Zsh / Bash / Fish** に対応しています。

## 特徴

- **マルチシェル対応**: 共通コア 1 本＋各シェル（Zsh / Bash 3.2+ / Fish）の薄いフックで構成。
- **余分な空アンカー Workspace を増やさない**: 現在の Workspace をアンカーにしてグループを作成（`--from "$CMUX_WORKSPACE_ID"`）するため、初回移動時に空タブが増えません。
- **別リポジトリ移動時のアンカー制約を自動解決**: 現在の Workspace が旧グループのアンカーになっていても、以下のように自動で処理します。
  - 旧グループに他メンバーが残っている場合：`cmux workspace-group set-anchor` でアンカー権限を移譲してから移動（旧グループを維持）
  - 自分だけのグループだった場合：`cmux workspace-group ungroup` で旧グループを解散してから移動（Workspace 自体は閉じない）
  - ピン留めされた空グループは勝手に消さず保護してスキップ
- **冪等なグルーピング**: `--idempotency-key "repo:<正規化パス>"` と `--id-format both` により、同じリポジトリの複数 Workspace を確実に同一グループへまとめます。
- **軽量設計**: 各シェル側で `$PWD` をキャッシュするため、ディレクトリが変わらない通常プロンプトではサブプロセスを一切起動しません。
- **cmux 外では完全 no-op**: `CMUX_WORKSPACE_ID` が無いターミナルではフック登録すらせずに終了します。

## 動作要件

- `workspace-group` サブコマンドおよび `--id-format both` に対応した [cmux](https://cmux.com/)（`0.65.2` で動作確認）
- `bash`（3.2+、macOS / Linux 標準搭載、共通コア実行用）
- `git`
- `jq`（macOS 15+ は標準搭載、未導入の場合は `brew install jq`）

## インストール

まずリポジトリを clone します：

```sh
git clone https://github.com/taiyop/cmux-autogroup.git ~/.config/cmux/cmux-autogroup
```

### Zsh

`~/.zshrc` の末尾付近（`PATH` 設定の後）に追記します：

```zsh
if [[ -n "${CMUX_WORKSPACE_ID:-}" && -r "$HOME/.config/cmux/cmux-autogroup/cmux-autogroup.plugin.zsh" ]]; then
  export CMUX_GROUP_BASE="$HOME/repos"
  source "$HOME/.config/cmux/cmux-autogroup/cmux-autogroup.plugin.zsh"
fi
```

Zsh プラグインマネージャでもそのまま導入できます：
- **Sheldon**:
  ```toml
  [plugins.cmux-autogroup]
  github = "taiyop/cmux-autogroup"
  ```
- **zinit**: `zinit light taiyop/cmux-autogroup`
- **antidote**: `taiyop/cmux-autogroup`
- **Oh My Zsh**: `${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/cmux-autogroup` に clone して `plugins=(... cmux-autogroup)` に追加

### Bash

`~/.bashrc`（または `~/.bash_profile`）の末尾付近に追記します：

```bash
if [[ -n "${CMUX_WORKSPACE_ID:-}" && -r "$HOME/.config/cmux/cmux-autogroup/init/cmux-autogroup.bash" ]]; then
  export CMUX_GROUP_BASE="$HOME/repos"
  source "$HOME/.config/cmux/cmux-autogroup/init/cmux-autogroup.bash"
fi
```

### Fish

`~/.config/fish/config.fish` に追記します：

```fish
if set -q CMUX_WORKSPACE_ID; and test -r "$HOME/.config/cmux/cmux-autogroup/init/cmux-autogroup.fish"
    set -gx CMUX_GROUP_BASE "$HOME/repos"
    source "$HOME/.config/cmux/cmux-autogroup/init/cmux-autogroup.fish"
end
```

## 設定オプション

フックを読み込む**前**に環境変数で指定できます。

| 環境変数 | デフォルト | 説明 |
| --- | --- | --- |
| `CMUX_GROUP_BASE` | `$HOME/Projects` | 自動グループ化の対象ディレクトリ。`:` 区切りで複数指定可能（例: `"$HOME/repos:$HOME/work"`）。空文字 `""` または `"*"` で全 Git リポジトリを対象にします。 |
| `CMUX_GROUP_WORKTREE_MODE` | `separate` | `separate`: worktree ごとに別グループ（`--show-toplevel`）。`shared`: worktree を親リポジトリのグループに統合（`--git-common-dir`）。 |
| `CMUX_GROUP_NAME_MODE` | `basename` | `basename`: リポジトリ末尾名（例: `app`）。`relative`: `CMUX_GROUP_BASE` からの相対パス（例: `team/app`）で同名リポジトリを区別。 |
| `CMUX_AUTO_GROUP_DEBUG` | `0` | `1` にするとエラーやスキップ理由を `stderr` に出力します。 |

## 構成

```text
cmux-autogroup/
├── bin/cmux-autogroup          # 共通コア（Bash 3.2+ 互換）
├── cmux-autogroup.plugin.zsh   # Zsh ラッパー（chpwd + 初回 precmd）
├── init/cmux-autogroup.bash    # Bash ラッパー（PROMPT_COMMAND）
├── init/cmux-autogroup.fish    # Fish ラッパー（--on-variable PWD）
└── tests/run_tests.bash        # コア＋各シェルラッパーの自動テスト
```

## 運用メモ

- **`⌘N`（New Workspace）**: cmux 標準の `workspaceInheritWorkingDirectory: true` により、同じリポジトリ配下（サブディレクトリ含む）で `⌘N` を押すと自動的に同じリポジトリのグループに入ります。
- **手動再同期**: `cmux-autogroup-sync`（デバッグ時は `CMUX_AUTO_GROUP_DEBUG=1 cmux-autogroup-sync`）でキャッシュを無視して再評価できます。
- **複数ペイン**: `CMUX_WORKSPACE_ID` は Workspace 全体で共通のため、別ペインで別リポジトリに `cd` すると Workspace 全体が移動します。
- **別ウィンドウ（`⌘⇧N`）**: cmux の Workspace Group はウィンドウ単位のため、別ウィンドウ側で独立したグループが作成されます。

## テスト

モックを使った自動テスト（cmux 本体の起動不要）：

```sh
bash tests/run_tests.bash
```

## ライセンス

[MIT](LICENSE)
