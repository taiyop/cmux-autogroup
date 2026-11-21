# init/cmux-autogroup.bash
# Bash hook wrapper for cmux-autogroup (Bash 3.2+ compatible).
# https://github.com/taiyop/cmux-autogroup

[[ -n "${CMUX_WORKSPACE_ID:-}" ]] || return 0

_CMUX_AUTOGROUP_ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
_CMUX_AUTOGROUP_BIN="${_CMUX_AUTOGROUP_ROOT}/bin/cmux-autogroup"

_cmux_auto_group() {
  local last_status=$?
  [[ -n "${CMUX_WORKSPACE_ID:-}" ]] || return "$last_status"
  [[ "${_CMUX_LAST_GROUP_PWD:-}" == "$PWD" ]] && return "$last_status"
  _CMUX_LAST_GROUP_PWD="$PWD"

  if [[ -x "$_CMUX_AUTOGROUP_BIN" ]]; then
    local synced_repo
    synced_repo=$(_CMUX_LAST_GROUP_REPO="${_CMUX_LAST_GROUP_REPO:-}" "$_CMUX_AUTOGROUP_BIN" sync "$PWD")
    if [[ -n "$synced_repo" ]]; then
      _CMUX_LAST_GROUP_REPO="$synced_repo"
    fi
  fi
  return "$last_status"
}

cmux-autogroup-sync() {
  unset _CMUX_LAST_GROUP_PWD _CMUX_LAST_GROUP_REPO
  _cmux_auto_group
}

# Register once in PROMPT_COMMAND (supports both Bash 5.1+ arrays and strings).
if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
  _cmux_already_registered=0
  for _cmux_pc in "${PROMPT_COMMAND[@]}"; do
    if [[ "$_cmux_pc" == "_cmux_auto_group" ]]; then
      _cmux_already_registered=1
      break
    fi
  done
  if (( _cmux_already_registered == 0 )); then
    PROMPT_COMMAND+=(_cmux_auto_group)
  fi
  unset _cmux_already_registered _cmux_pc
else
  case ";${PROMPT_COMMAND:-};" in
    *";_cmux_auto_group;"*|*" _cmux_auto_group;"*|*";_cmux_auto_group "*)
      ;;
    ";;")
      PROMPT_COMMAND="_cmux_auto_group"
      ;;
    *)
      PROMPT_COMMAND="_cmux_auto_group; ${PROMPT_COMMAND}"
      ;;
  esac
fi
