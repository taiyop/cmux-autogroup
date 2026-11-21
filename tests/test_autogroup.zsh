#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PLUGIN_PATH="${SCRIPT_DIR:h}/cmux-autogroup.plugin.zsh"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# Resolve symlinks (e.g. /var -> /private/var on macOS)
TMP_ROOT="${TMP_ROOT:A}"

# Create fixture git repositories
mkdir -p "$TMP_ROOT/base1/org/repo-a/sub" "$TMP_ROOT/base1/repo-b" "$TMP_ROOT/base2/repo-c" "$TMP_ROOT/outside/repo-out"

init_repo() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" config user.name "Test"
  git -C "$dir" config user.email "test@example.com"
  touch "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "init"
}

init_repo "$TMP_ROOT/base1/org/repo-a"
init_repo "$TMP_ROOT/base1/repo-b"
init_repo "$TMP_ROOT/base2/repo-c"
init_repo "$TMP_ROOT/outside/repo-out"
git -C "$TMP_ROOT/base1/org/repo-a" worktree add -q "$TMP_ROOT/base1/repo-a-wt" -b wt-branch

REPO_A="$TMP_ROOT/base1/org/repo-a"
REPO_A_WT="$TMP_ROOT/base1/repo-a-wt"
REPO_B="$TMP_ROOT/base1/repo-b"
REPO_C="$TMP_ROOT/base2/repo-c"
REPO_OUT="$TMP_ROOT/outside/repo-out"

MOCK_LOG="$TMP_ROOT/cmux_calls.log"
MOCK_LIST_FILE="$TMP_ROOT/mock_list.json"
MOCK_LIST_AFTER_FILE="$TMP_ROOT/mock_list_after.json"
MOCK_CREATE_FILE="$TMP_ROOT/mock_create.json"
MOCK_LIST_COUNT_FILE="$TMP_ROOT/mock_list_count"
MOCK_FAIL_ADD_FILE="$TMP_ROOT/mock_fail_add"

# Mock cmux command
cmux() {
  print -r -- "$*" >> "$MOCK_LOG"

  # Strip leading global flags (--id-format <val>)
  local -a args=("$@")
  while (( ${#args} > 0 )) && [[ "${args[1]}" == --* ]]; do
    if [[ "${args[1]}" == "--id-format" ]]; then
      args=("${args[@]:2}")
    else
      args=("${args[@]:1}")
    fi
  done

  if [[ "${args[1]:-}" == "workspace-group" ]]; then
    case "${args[2]:-}" in
      list)
        local n=0
        [[ -f "$MOCK_LIST_COUNT_FILE" ]] && n=$(<"$MOCK_LIST_COUNT_FILE")
        n=$((n + 1))
        print -r -- "$n" > "$MOCK_LIST_COUNT_FILE"
        if (( n > 1 )) && [[ -f "$MOCK_LIST_AFTER_FILE" ]]; then
          cat "$MOCK_LIST_AFTER_FILE"
        else
          cat "$MOCK_LIST_FILE"
        fi
        return 0
        ;;
      create)
        cat "$MOCK_CREATE_FILE"
        return 0
        ;;
      add)
        if [[ -f "$MOCK_FAIL_ADD_FILE" ]]; then
          print -u2 -- "simulated add failure"
          return 1
        fi
        return 0
        ;;
      set-anchor|ungroup)
        return 0
        ;;
    esac
  fi
  return 0
}

reset_mock() {
  : > "$MOCK_LOG"
  print -r -- '{"groups":[]}' > "$MOCK_LIST_FILE"
  rm -f "$MOCK_LIST_AFTER_FILE" "$MOCK_FAIL_ADD_FILE"
  print -r -- "0" > "$MOCK_LIST_COUNT_FILE"
  print -r -- '{"id":"G-NEW","ref":"workspace_group:99"}' > "$MOCK_CREATE_FILE"
  unset _CMUX_LAST_GROUP_PWD _CMUX_LAST_GROUP_REPO
}

FAILURES=0
assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    print -r -- "PASS: $label"
  else
    print -u2 -- "FAIL: $label"
    print -u2 -- "  expected to contain: $expected"
    print -u2 -- "  actual: $actual"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    print -r -- "PASS: $label"
  else
    print -u2 -- "FAIL: $label"
    print -u2 -- "  expected: <$expected>"
    print -u2 -- "  actual:   <$actual>"
    FAILURES=$((FAILURES + 1))
  fi
}

export CMUX_WORKSPACE_ID="11111111-1111-1111-1111-111111111111"
export CMUX_GROUP_BASE="$TMP_ROOT/base1"
source "$PLUGIN_PATH"

# Test 1: New repository (from subdirectory) creates group with --from current workspace
reset_mock
cat <<EOF > "$MOCK_LIST_AFTER_FILE"
{"groups":[{"id":"G-NEW","anchor_workspace_id":"$CMUX_WORKSPACE_ID","member_workspace_ids":["$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_A","is_pinned":false}]}
EOF
cd "$REPO_A/sub"
_cmux_auto_group
calls=$(<"$MOCK_LOG")
assert_contains "Test 1: creates group with --from workspace" "workspace-group create --json --name repo-a --cwd $REPO_A --from $CMUX_WORKSPACE_ID --idempotency-key repo:$REPO_A" "$calls"
assert_eq "Test 1: caches repo" "$REPO_A" "${_CMUX_LAST_GROUP_REPO:-}"

# Test 2: Moving from lone anchor (repo-a) to existing group (repo-b) -> ungroup then add
reset_mock
cat <<EOF > "$MOCK_LIST_FILE"
{"groups":[
  {"id":"G-A","anchor_workspace_id":"$CMUX_WORKSPACE_ID","member_workspace_ids":["$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_A","is_pinned":false},
  {"id":"G-B","anchor_workspace_id":"22222222-2222-2222-2222-222222222222","member_workspace_ids":["22222222-2222-2222-2222-222222222222"],"idempotency_key":"repo:$REPO_B","is_pinned":false}
]}
EOF
cd "$REPO_B"
_cmux_auto_group
calls=$(<"$MOCK_LOG")
assert_contains "Test 2: ungroups lone old anchor" "workspace-group ungroup G-A" "$calls"
assert_contains "Test 2: adds workspace to existing group G-B" "workspace-group add --group G-B --workspace $CMUX_WORKSPACE_ID" "$calls"
assert_eq "Test 2: caches repo-b" "$REPO_B" "${_CMUX_LAST_GROUP_REPO:-}"

# Test 3: Moving from multi-member anchor (repo-a) to new repo (repo-b) -> set-anchor then create
reset_mock
cat <<EOF > "$MOCK_LIST_FILE"
{"groups":[
  {"id":"G-A","anchor_workspace_id":"$CMUX_WORKSPACE_ID","member_workspace_ids":["$CMUX_WORKSPACE_ID","33333333-3333-3333-3333-333333333333"],"idempotency_key":"repo:$REPO_A","is_pinned":false}
]}
EOF
cat <<EOF > "$MOCK_LIST_AFTER_FILE"
{"groups":[
  {"id":"G-A","anchor_workspace_id":"33333333-3333-3333-3333-333333333333","member_workspace_ids":["33333333-3333-3333-3333-333333333333"],"idempotency_key":"repo:$REPO_A","is_pinned":false},
  {"id":"G-NEW","anchor_workspace_id":"$CMUX_WORKSPACE_ID","member_workspace_ids":["$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_B","is_pinned":false}
]}
EOF
cd "$REPO_B"
_cmux_auto_group
calls=$(<"$MOCK_LOG")
assert_contains "Test 3: transfers anchor to next member" "workspace-group set-anchor --group G-A --workspace 33333333-3333-3333-3333-333333333333" "$calls"
assert_contains "Test 3: creates new group for repo-b" "workspace-group create --json --name repo-b --cwd $REPO_B --from $CMUX_WORKSPACE_ID --idempotency-key repo:$REPO_B" "$calls"

# Test 4: Pinned empty anchor is protected and not ungrouped
reset_mock
cat <<EOF > "$MOCK_LIST_FILE"
{"groups":[
  {"id":"G-PIN","anchor_workspace_id":"$CMUX_WORKSPACE_ID","member_workspace_ids":["$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_A","is_pinned":true},
  {"id":"G-B","anchor_workspace_id":"22222222-2222-2222-2222-222222222222","member_workspace_ids":["22222222-2222-2222-2222-222222222222"],"idempotency_key":"repo:$REPO_B","is_pinned":false}
]}
EOF
cd "$REPO_B"
_cmux_auto_group
calls=$(<"$MOCK_LOG")
assert_eq "Test 4: only list called (no ungroup/add)" "--id-format both workspace-group list --json" "$calls"
assert_eq "Test 4: repo cache stays empty" "" "${_CMUX_LAST_GROUP_REPO:-}"

# Test 5: Already a member of target group -> no-op
reset_mock
cat <<EOF > "$MOCK_LIST_FILE"
{"groups":[
  {"id":"G-A","anchor_workspace_id":"22222222-2222-2222-2222-222222222222","member_workspace_ids":["22222222-2222-2222-2222-222222222222","$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_A","is_pinned":false}
]}
EOF
cd "$REPO_A"
_cmux_auto_group
calls=$(<"$MOCK_LOG")
assert_eq "Test 5: already in group does not call add/create" "--id-format both workspace-group list --json" "$calls"
assert_eq "Test 5: caches repo-a" "$REPO_A" "${_CMUX_LAST_GROUP_REPO:-}"

# Test 6: Outside CMUX_GROUP_BASE -> skipped completely
reset_mock
cd "$REPO_OUT"
_cmux_auto_group
calls=$(<"$MOCK_LOG")
assert_eq "Test 6: outside base does not invoke cmux" "" "$calls"

# Test 7: Multiple CMUX_GROUP_BASE paths + relative name mode
reset_mock
CMUX_GROUP_BASE="$TMP_ROOT/base1:$TMP_ROOT/base2"
CMUX_GROUP_NAME_MODE="relative"
cat <<EOF > "$MOCK_LIST_AFTER_FILE"
{"groups":[{"id":"G-NEW","anchor_workspace_id":"$CMUX_WORKSPACE_ID","member_workspace_ids":["$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_A","is_pinned":false}]}
EOF
cd "$REPO_A"
_cmux_auto_group
calls=$(<"$MOCK_LOG")
assert_contains "Test 7a: relative group name org/repo-a" "--name org/repo-a" "$calls"

reset_mock
cat <<EOF > "$MOCK_LIST_AFTER_FILE"
{"groups":[{"id":"G-NEW","anchor_workspace_id":"$CMUX_WORKSPACE_ID","member_workspace_ids":["$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_C","is_pinned":false}]}
EOF
cd "$REPO_C"
_cmux_auto_group
calls=$(<"$MOCK_LOG")
assert_contains "Test 7b: second base path matches repo-c" "--idempotency-key repo:$REPO_C" "$calls"
CMUX_GROUP_NAME_MODE="basename"
CMUX_GROUP_BASE="$TMP_ROOT/base1"

# Test 8: Worktree shared mode maps worktree back to main repo root
reset_mock
CMUX_GROUP_WORKTREE_MODE="shared"
cat <<EOF > "$MOCK_LIST_AFTER_FILE"
{"groups":[{"id":"G-NEW","anchor_workspace_id":"$CMUX_WORKSPACE_ID","member_workspace_ids":["$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_A","is_pinned":false}]}
EOF
cd "$REPO_A_WT"
_cmux_auto_group
calls=$(<"$MOCK_LOG")
assert_contains "Test 8: shared worktree mode uses main repo key" "--idempotency-key repo:$REPO_A" "$calls"
CMUX_GROUP_WORKTREE_MODE="separate"

# Test 9: Failed add does not poison _CMUX_LAST_GROUP_REPO
reset_mock
touch "$MOCK_FAIL_ADD_FILE"
cat <<EOF > "$MOCK_LIST_FILE"
{"groups":[
  {"id":"G-B","anchor_workspace_id":"22222222-2222-2222-2222-222222222222","member_workspace_ids":["22222222-2222-2222-2222-222222222222"],"idempotency_key":"repo:$REPO_B","is_pinned":false}
]}
EOF
cd "$REPO_B"
_cmux_auto_group
assert_eq "Test 9: failed add leaves _CMUX_LAST_GROUP_REPO unset" "" "${_CMUX_LAST_GROUP_REPO:-}"

# Test 10: cmux-autogroup-sync retries cleanly once add recovers
rm -f "$MOCK_FAIL_ADD_FILE"
: > "$MOCK_LOG"
cmux-autogroup-sync
calls=$(<"$MOCK_LOG")
assert_contains "Test 10: cmux-autogroup-sync retries add" "workspace-group add --group G-B --workspace $CMUX_WORKSPACE_ID" "$calls"
assert_eq "Test 10: caches repo-b after recovery" "$REPO_B" "${_CMUX_LAST_GROUP_REPO:-}"

if (( FAILURES > 0 )); then
  print -u2 -- "$FAILURES test(s) failed."
  exit 1
fi
print -r -- "All tests passed!"
