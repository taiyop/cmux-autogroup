# cmux-autogroup.plugin.zsh
# Zsh hook wrapper for cmux-autogroup.
# https://github.com/taiyop/cmux-autogroup

[[ -n "${CMUX_WORKSPACE_ID:-}" ]] || return 0

_CMUX_AUTOGROUP_BIN="${${(%):-%x}:A:h}/bin/cmux-autogroup"

_cmux_auto_group() {
  [[ -n "${CMUX_WORKSPACE_ID:-}" ]] || return 0
  [[ "${_CMUX_LAST_GROUP_PWD:-}" == "$PWD" ]] && return 0
  _CMUX_LAST_GROUP_PWD="$PWD"

  [[ -x "$_CMUX_AUTOGROUP_BIN" ]] || return 0

  local synced_repo
  synced_repo=$(_CMUX_LAST_GROUP_REPO="${_CMUX_LAST_GROUP_REPO:-}" "$_CMUX_AUTOGROUP_BIN" sync "$PWD")
  [[ -n "$synced_repo" ]] && _CMUX_LAST_GROUP_REPO="$synced_repo"
  return 0
}

cmux-autogroup-sync() {
  unset _CMUX_LAST_GROUP_PWD _CMUX_LAST_GROUP_REPO
  _cmux_auto_group
}

_cmux_auto_group_init() {
  add-zsh-hook -d precmd _cmux_auto_group_init
  _cmux_auto_group
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _cmux_auto_group
add-zsh-hook precmd _cmux_auto_group_init
