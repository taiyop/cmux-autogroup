# init/cmux-autogroup.fish
# Fish hook wrapper for cmux-autogroup.
# https://github.com/taiyop/cmux-autogroup

if not set -q CMUX_WORKSPACE_ID; or test -z "$CMUX_WORKSPACE_ID"
    return 0
end

set -g _CMUX_AUTOGROUP_BIN (sh -c 'cd -P -- "$(dirname -- "$1")/.." && pwd -P' _ (status filename))"/bin/cmux-autogroup"

function _cmux_auto_group --on-variable PWD
    set -l last_status $status
    if not set -q CMUX_WORKSPACE_ID; or test -z "$CMUX_WORKSPACE_ID"
        return $last_status
    end
    if set -q _CMUX_LAST_GROUP_PWD; and test "$_CMUX_LAST_GROUP_PWD" = "$PWD"
        return $last_status
    end
    set -g _CMUX_LAST_GROUP_PWD "$PWD"

    if test -x "$_CMUX_AUTOGROUP_BIN"
        set -l prev_repo ""
        if set -q _CMUX_LAST_GROUP_REPO
            set prev_repo "$_CMUX_LAST_GROUP_REPO"
        end
        set -l synced_repo (env _CMUX_LAST_GROUP_REPO="$prev_repo" "$_CMUX_AUTOGROUP_BIN" sync "$PWD")
        if test -n "$synced_repo"
            set -g _CMUX_LAST_GROUP_REPO "$synced_repo"
        end
    end
    return $last_status
end

function cmux-autogroup-sync --description "Force re-sync current cmux workspace group"
    set -e _CMUX_LAST_GROUP_PWD
    set -e _CMUX_LAST_GROUP_REPO
    _cmux_auto_group
end

function _cmux_auto_group_init --on-event fish_prompt
    functions -e _cmux_auto_group_init
    _cmux_auto_group
end
