# cmux-autogroup.plugin.zsh
# Automatically group cmux workspaces by git repository root.
# https://github.com/taiyop/cmux-autogroup

# Only activate inside a cmux workspace session.
[[ -n "${CMUX_WORKSPACE_ID:-}" ]] || return 0

# Default target base directory (colon-separated paths; empty or "*" matches all repos).
if ! (( ${+CMUX_GROUP_BASE} )); then
  export CMUX_GROUP_BASE="$HOME/Projects"
fi

# Worktree handling: "separate" (per worktree) or "shared" (group worktrees by main repo).
: "${CMUX_GROUP_WORKTREE_MODE:=separate}"

# Group display name: "basename" (e.g. "app") or "relative" (e.g. "team/app").
: "${CMUX_GROUP_NAME_MODE:=basename}"

_cmux_auto_group_log() {
  [[ "${CMUX_AUTO_GROUP_DEBUG:-0}" == "1" ]] && print -u2 -- "[cmux-autogroup] $*"
  return 0
}

_cmux_auto_group_expand_tilde() {
  local p="$1"
  if [[ "$p" == "~" ]]; then
    print -r -- "$HOME"
  elif [[ "$p" == "~/"* ]]; then
    print -r -- "$HOME/${p#\~/}"
  else
    print -r -- "$p"
  fi
}

# Release current workspace if it is the anchor of a different group.
# Returns 0 when released (or not an anchor of another group), 1 if blocked (e.g. pinned empty group).
_cmux_release_if_other_anchor() {
  local ws_lower="$1"
  local target_group_lower="${2:-}"
  local list_json="$3"

  local anchor_info
  anchor_info=$(printf '%s' "$list_json" | jq -r --arg ws "$ws_lower" '
    first(
      (.groups // .)[]
      | select((.anchor_workspace_id // "" | ascii_downcase) == $ws)
    ) // empty
    | [
        (.id // .group_id // .ref // .group_ref // ""),
        ((.member_workspace_ids // []) | map(select(ascii_downcase != $ws)) | .[0] // ""),
        ((.is_pinned // .pinned // false) | tostring)
      ]
    | join("\n")
  ' 2>/dev/null) || return 0

  [[ -n "$anchor_info" ]] || return 0

  local -a lines
  lines=("${(@f)anchor_info}")
  local old_group="${lines[1]}"
  local next_member="${lines[2]}"
  local is_pinned="${lines[3]}"

  # Already the anchor of the target group.
  if [[ -n "$target_group_lower" && "${old_group:l}" == "$target_group_lower" ]]; then
    return 0
  fi

  local err
  if [[ -n "$next_member" ]]; then
    # Hand off anchor ownership to another member so the old group stays intact.
    if ! err=$(cmux workspace-group set-anchor \
      --group "$old_group" \
      --workspace "$next_member" 2>&1 >/dev/null); then
      _cmux_auto_group_log "set-anchor failed: $err"
      return 1
    fi
  elif [[ "$is_pinned" == "true" ]]; then
    # Preserve pinned empty groups instead of unpinning/deleting them automatically.
    _cmux_auto_group_log "skip moving anchor of pinned empty group: $old_group"
    return 1
  else
    # Dissolve the now-empty group without closing the workspace.
    if ! err=$(cmux workspace-group ungroup "$old_group" 2>&1 >/dev/null); then
      _cmux_auto_group_log "ungroup failed: $err"
      return 1
    fi
  fi

  return 0
}

_cmux_auto_group() {
  [[ -n "${CMUX_WORKSPACE_ID:-}" ]] || return 0
  command -v cmux >/dev/null && command -v jq >/dev/null && command -v git >/dev/null || return 0

  # Avoid spawning git if PWD has not changed.
  [[ "${_CMUX_LAST_GROUP_PWD:-}" == "$PWD" ]] && return 0
  _CMUX_LAST_GROUP_PWD="$PWD"

  local repo=""
  if [[ "${CMUX_GROUP_WORKTREE_MODE:-separate}" == "shared" ]]; then
    local common_dir
    common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || return 0
    [[ "$common_dir" == /* ]] || common_dir="$PWD/$common_dir"
    common_dir="${common_dir:A}"
    if [[ "${common_dir:t}" == ".git" ]]; then
      repo="${common_dir:h}"
    else
      repo="$common_dir"
    fi
  else
    repo=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  fi

  # Resolve symlinks for canonical comparison and idempotency keys.
  repo="${repo:A}"

  # Filter by CMUX_GROUP_BASE (empty or "*" allows any git repository).
  local matched_base=""
  if [[ -z "${CMUX_GROUP_BASE:-}" || "$CMUX_GROUP_BASE" == "*" ]]; then
    matched_base="/"
  else
    local raw_base resolved_base
    local -a bases
    bases=("${(@s.:.)CMUX_GROUP_BASE}")
    for raw_base in "${bases[@]}"; do
      [[ -n "$raw_base" ]] || continue
      resolved_base=$(_cmux_auto_group_expand_tilde "$raw_base")
      resolved_base="${resolved_base:A}"
      if [[ "$repo" == "$resolved_base" || "$repo" == "$resolved_base/"* ]]; then
        matched_base="$resolved_base"
        break
      fi
    done
    [[ -n "$matched_base" ]] || return 0
  fi

  # Skip if already synced to this repository.
  [[ "${_CMUX_LAST_GROUP_REPO:-}" == "$repo" ]] && return 0

  local group_name="${repo:t}"
  if [[ "${CMUX_GROUP_NAME_MODE:-basename}" == "relative" && "$matched_base" != "/" && "$repo" == "$matched_base/"* ]]; then
    group_name="${repo#"$matched_base/"}"
  fi

  local ws_lower="${CMUX_WORKSPACE_ID:l}"
  local key="repo:$repo"
  local list_json existing_group create_out target_group err

  # Request both UUIDs and refs so CMUX_WORKSPACE_ID (UUID) matches reliably.
  list_json=$(cmux --id-format both workspace-group list --json 2>/dev/null) || {
    _cmux_auto_group_log "workspace-group list failed"
    return 0
  }

  # Look up an existing group for this repository by idempotency_key / external_id.
  existing_group=$(printf '%s' "$list_json" | jq -r --arg key "$key" '
    first(
      (.groups // .)[]
      | select((.idempotency_key // .external_id // "") == $key)
      | (.id // .group_id // .ref // .group_ref // "")
    ) // empty
  ' 2>/dev/null)

  if [[ -n "$existing_group" ]]; then
    # Already a member or anchor of this group.
    if printf '%s' "$list_json" | jq -e --arg ws "$ws_lower" --arg tg "${existing_group:l}" '
      (.groups // .)[]
      | select(
          ((.id // .group_id // "") | ascii_downcase) == $tg
          or ((.ref // .group_ref // "") | ascii_downcase) == $tg
        )
      | ((.anchor_workspace_id // "" | ascii_downcase) == $ws)
        or (((.member_workspace_ids // []) | map(ascii_downcase) | index($ws)) != null)
    ' >/dev/null 2>&1; then
      _CMUX_LAST_GROUP_REPO="$repo"
      return 0
    fi

    _cmux_release_if_other_anchor "$ws_lower" "${existing_group:l}" "$list_json" || return 0

    if err=$(cmux workspace-group add \
      --group "$existing_group" \
      --workspace "$CMUX_WORKSPACE_ID" 2>&1 >/dev/null); then
      _CMUX_LAST_GROUP_REPO="$repo"
    else
      _cmux_auto_group_log "add failed: $err"
    fi
    return 0
  fi

  # No group exists for this repository yet: release old anchor if needed, then create one
  # using the current workspace as its anchor (avoids spawning an extra empty anchor workspace).
  _cmux_release_if_other_anchor "$ws_lower" "" "$list_json" || return 0

  if ! create_out=$(cmux --id-format both workspace-group create --json \
    --name "$group_name" \
    --cwd "$repo" \
    --from "$CMUX_WORKSPACE_ID" \
    --idempotency-key "$key" 2>&1); then
    _cmux_auto_group_log "create failed: $create_out"
    return 0
  fi

  target_group=$(printf '%s' "$create_out" | jq -r '
    .id // .group_id // .ref // .group_ref
    // .group.id // .group.group_id // .group.ref // .group.group_ref
    // empty
  ' 2>/dev/null)
  if [[ -z "$target_group" && "$create_out" =~ 'workspace_group:[0-9]+' ]]; then
    target_group="$MATCH"
  fi
  [[ -n "$target_group" ]] || {
    _cmux_auto_group_log "could not parse target group from: $create_out"
    return 0
  }

  # Verify membership (handles the rare case where a concurrent create returned an existing group).
  list_json=$(cmux --id-format both workspace-group list --json 2>/dev/null) || {
    _CMUX_LAST_GROUP_REPO="$repo"
    return 0
  }
  if printf '%s' "$list_json" | jq -e --arg ws "$ws_lower" --arg tg "${target_group:l}" '
    (.groups // .)[]
    | select(
        ((.id // .group_id // "") | ascii_downcase) == $tg
        or ((.ref // .group_ref // "") | ascii_downcase) == $tg
      )
    | ((.anchor_workspace_id // "" | ascii_downcase) == $ws)
      or (((.member_workspace_ids // []) | map(ascii_downcase) | index($ws)) != null)
  ' >/dev/null 2>&1; then
    _CMUX_LAST_GROUP_REPO="$repo"
    return 0
  fi

  if err=$(cmux workspace-group add \
    --group "$target_group" \
    --workspace "$CMUX_WORKSPACE_ID" 2>&1 >/dev/null); then
    _CMUX_LAST_GROUP_REPO="$repo"
  else
    _cmux_auto_group_log "add after create failed: $err"
  fi
}

# Manual helper to force re-syncing the current workspace.
cmux-autogroup-sync() {
  unset _CMUX_LAST_GROUP_PWD _CMUX_LAST_GROUP_REPO
  _cmux_auto_group
}

# Run once on first prompt, then rely on chpwd for directory changes.
_cmux_auto_group_init() {
  add-zsh-hook -d precmd _cmux_auto_group_init
  _cmux_auto_group
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _cmux_auto_group
add-zsh-hook precmd _cmux_auto_group_init
