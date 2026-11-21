#!/usr/bin/env bash
# Comprehensive test suite for cmux-autogroup (core + bash/zsh/fish wrappers).
# Bash 3.2+ compatible.
set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P -- "$SCRIPT_DIR/.." && pwd -P)"
BIN_PATH="$REPO_ROOT/bin/cmux-autogroup"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
TMP_ROOT="$(cd -P -- "$TMP_ROOT" && pwd -P)"

# Fixture git repositories
mkdir -p \
  "$TMP_ROOT/base1/org/repo-a/sub" \
  "$TMP_ROOT/base1/repo-b" \
  "$TMP_ROOT/base2/repo-c" \
  "$TMP_ROOT/outside/repo-out" \
  "$TMP_ROOT/mock-bin"

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

export MOCK_LOG="$TMP_ROOT/cmux_calls.log"
export MOCK_LIST_FILE="$TMP_ROOT/mock_list.json"
export MOCK_LIST_AFTER_FILE="$TMP_ROOT/mock_list_after.json"
export MOCK_CREATE_FILE="$TMP_ROOT/mock_create.json"
export MOCK_LIST_COUNT_FILE="$TMP_ROOT/mock_list_count"
export MOCK_FAIL_ADD_FILE="$TMP_ROOT/mock_fail_add"

# Executable mock `cmux` in PATH
cat <<'EOF' > "$TMP_ROOT/mock-bin/cmux"
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_LOG"

while [[ $# -gt 0 && "$1" == --* ]]; do
  if [[ "$1" == "--id-format" ]]; then
    shift 2
  else
    shift 1
  fi
done

if [[ "${1:-}" == "workspace-group" ]]; then
  case "${2:-}" in
    list)
      n=0
      [[ -f "$MOCK_LIST_COUNT_FILE" ]] && n="$(cat "$MOCK_LIST_COUNT_FILE")"
      n=$((n + 1))
      printf '%s\n' "$n" > "$MOCK_LIST_COUNT_FILE"
      if (( n > 1 )) && [[ -f "$MOCK_LIST_AFTER_FILE" ]]; then
        cat "$MOCK_LIST_AFTER_FILE"
      else
        cat "$MOCK_LIST_FILE"
      fi
      exit 0
      ;;
    create)
      cat "$MOCK_CREATE_FILE"
      exit 0
      ;;
    add)
      if [[ -f "$MOCK_FAIL_ADD_FILE" ]]; then
        printf 'simulated add failure\n' >&2
        exit 1
      fi
      exit 0
      ;;
    set-anchor|ungroup)
      exit 0
      ;;
  esac
fi
exit 0
EOF
chmod +x "$TMP_ROOT/mock-bin/cmux"
export PATH="$TMP_ROOT/mock-bin:$PATH"

reset_mock() {
  : > "$MOCK_LOG"
  printf '{"groups":[]}\n' > "$MOCK_LIST_FILE"
  rm -f "$MOCK_LIST_AFTER_FILE" "$MOCK_FAIL_ADD_FILE"
  printf '0\n' > "$MOCK_LIST_COUNT_FILE"
  printf '{"id":"G-NEW","ref":"workspace_group:99"}\n' > "$MOCK_CREATE_FILE"
}

FAILURES=0
assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    printf 'PASS: %s\n' "$label"
  else
    printf 'FAIL: %s\n  expected to contain: %s\n  actual: %s\n' "$label" "$expected" "$actual" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf 'PASS: %s\n' "$label"
  else
    printf 'FAIL: %s\n  expected: <%s>\n  actual:   <%s>\n' "$label" "$expected" "$actual" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

export CMUX_WORKSPACE_ID="11111111-1111-1111-1111-111111111111"
export CMUX_GROUP_BASE="$TMP_ROOT/base1"

# ---------------------------------------------------------------------------
# Core tests (bin/cmux-autogroup)
# ---------------------------------------------------------------------------

# Test 1: New repository (from subdirectory) creates group with --from current workspace
reset_mock
cat <<EOF > "$MOCK_LIST_AFTER_FILE"
{"groups":[{"id":"G-NEW","anchor_workspace_id":"$CMUX_WORKSPACE_ID","member_workspace_ids":["$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_A","is_pinned":false}]}
EOF
out="$("$BIN_PATH" sync "$REPO_A/sub")"
calls="$(cat "$MOCK_LOG")"
assert_contains "Core 1: creates group with --from workspace" "workspace-group create --json --name repo-a --cwd $REPO_A --from $CMUX_WORKSPACE_ID --idempotency-key repo:$REPO_A" "$calls"
assert_eq "Core 1: returns synced repo path" "$REPO_A" "$out"

# Test 2: Moving from lone anchor (repo-a) to existing group (repo-b) -> ungroup then add
reset_mock
cat <<EOF > "$MOCK_LIST_FILE"
{"groups":[
  {"id":"G-A","anchor_workspace_id":"$CMUX_WORKSPACE_ID","member_workspace_ids":["$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_A","is_pinned":false},
  {"id":"G-B","anchor_workspace_id":"22222222-2222-2222-2222-222222222222","member_workspace_ids":["22222222-2222-2222-2222-222222222222"],"idempotency_key":"repo:$REPO_B","is_pinned":false}
]}
EOF
out="$("$BIN_PATH" sync "$REPO_B")"
calls="$(cat "$MOCK_LOG")"
assert_contains "Core 2: ungroups lone old anchor" "workspace-group ungroup G-A" "$calls"
assert_contains "Core 2: adds workspace to existing group G-B" "workspace-group add --group G-B --workspace $CMUX_WORKSPACE_ID" "$calls"
assert_eq "Core 2: returns synced repo-b" "$REPO_B" "$out"

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
out="$("$BIN_PATH" sync "$REPO_B")"
calls="$(cat "$MOCK_LOG")"
assert_contains "Core 3: transfers anchor to next member" "workspace-group set-anchor --group G-A --workspace 33333333-3333-3333-3333-333333333333" "$calls"
assert_contains "Core 3: creates new group for repo-b" "workspace-group create --json --name repo-b --cwd $REPO_B --from $CMUX_WORKSPACE_ID --idempotency-key repo:$REPO_B" "$calls"
assert_eq "Core 3: returns synced repo-b" "$REPO_B" "$out"

# Test 4: Pinned empty anchor is protected and not ungrouped
reset_mock
cat <<EOF > "$MOCK_LIST_FILE"
{"groups":[
  {"id":"G-PIN","anchor_workspace_id":"$CMUX_WORKSPACE_ID","member_workspace_ids":["$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_A","is_pinned":true},
  {"id":"G-B","anchor_workspace_id":"22222222-2222-2222-2222-222222222222","member_workspace_ids":["22222222-2222-2222-2222-222222222222"],"idempotency_key":"repo:$REPO_B","is_pinned":false}
]}
EOF
out="$("$BIN_PATH" sync "$REPO_B")"
calls="$(cat "$MOCK_LOG")"
assert_eq "Core 4: only list called (no ungroup/add)" "--id-format both workspace-group list --json" "$calls"
assert_eq "Core 4: stdout empty on skip" "" "$out"

# Test 5: Already a member of target group -> no-op, returns repo path
reset_mock
cat <<EOF > "$MOCK_LIST_FILE"
{"groups":[
  {"id":"G-A","anchor_workspace_id":"22222222-2222-2222-2222-222222222222","member_workspace_ids":["22222222-2222-2222-2222-222222222222","$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_A","is_pinned":false}
]}
EOF
out="$("$BIN_PATH" sync "$REPO_A")"
calls="$(cat "$MOCK_LOG")"
assert_eq "Core 5: already in group does not call add/create" "--id-format both workspace-group list --json" "$calls"
assert_eq "Core 5: returns repo-a" "$REPO_A" "$out"

# Test 6: Outside CMUX_GROUP_BASE -> skipped completely
reset_mock
out="$("$BIN_PATH" sync "$REPO_OUT")"
calls="$(cat "$MOCK_LOG")"
assert_eq "Core 6: outside base does not invoke cmux" "" "$calls"
assert_eq "Core 6: stdout empty" "" "$out"

# Test 7: Multiple CMUX_GROUP_BASE paths + relative name mode
reset_mock
cat <<EOF > "$MOCK_LIST_AFTER_FILE"
{"groups":[{"id":"G-NEW","anchor_workspace_id":"$CMUX_WORKSPACE_ID","member_workspace_ids":["$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_A","is_pinned":false}]}
EOF
out="$(CMUX_GROUP_BASE="$TMP_ROOT/base1:$TMP_ROOT/base2" CMUX_GROUP_NAME_MODE=relative "$BIN_PATH" sync "$REPO_A")"
calls="$(cat "$MOCK_LOG")"
assert_contains "Core 7a: relative group name org/repo-a" "--name org/repo-a" "$calls"
assert_eq "Core 7a: returns repo-a" "$REPO_A" "$out"

reset_mock
cat <<EOF > "$MOCK_LIST_AFTER_FILE"
{"groups":[{"id":"G-NEW","anchor_workspace_id":"$CMUX_WORKSPACE_ID","member_workspace_ids":["$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_C","is_pinned":false}]}
EOF
out="$(CMUX_GROUP_BASE="$TMP_ROOT/base1:$TMP_ROOT/base2" "$BIN_PATH" sync "$REPO_C")"
calls="$(cat "$MOCK_LOG")"
assert_contains "Core 7b: second base path matches repo-c" "--idempotency-key repo:$REPO_C" "$calls"

# Test 8: Worktree shared mode maps worktree back to main repo root
reset_mock
cat <<EOF > "$MOCK_LIST_AFTER_FILE"
{"groups":[{"id":"G-NEW","anchor_workspace_id":"$CMUX_WORKSPACE_ID","member_workspace_ids":["$CMUX_WORKSPACE_ID"],"idempotency_key":"repo:$REPO_A","is_pinned":false}]}
EOF
out="$(CMUX_GROUP_WORKTREE_MODE=shared "$BIN_PATH" sync "$REPO_A_WT")"
calls="$(cat "$MOCK_LOG")"
assert_contains "Core 8: shared worktree mode uses main repo key" "--idempotency-key repo:$REPO_A" "$calls"
assert_eq "Core 8: returns main repo path" "$REPO_A" "$out"

# Test 9: Failed add emits nothing (so caller does not cache failure)
reset_mock
touch "$MOCK_FAIL_ADD_FILE"
cat <<EOF > "$MOCK_LIST_FILE"
{"groups":[
  {"id":"G-B","anchor_workspace_id":"22222222-2222-2222-2222-222222222222","member_workspace_ids":["22222222-2222-2222-2222-222222222222"],"idempotency_key":"repo:$REPO_B","is_pinned":false}
]}
EOF
out="$("$BIN_PATH" sync "$REPO_B")"
assert_eq "Core 9: failed add emits empty stdout" "" "$out"

# ---------------------------------------------------------------------------
# Wrapper integration tests (Bash / Zsh / Fish)
# ---------------------------------------------------------------------------

# Bash wrapper test (preserves $? and supports cmux-autogroup-sync)
reset_mock
cat <<EOF > "$MOCK_LIST_FILE"
{"groups":[
  {"id":"G-B","anchor_workspace_id":"22222222-2222-2222-2222-222222222222","member_workspace_ids":["22222222-2222-2222-2222-222222222222"],"idempotency_key":"repo:$REPO_B","is_pinned":false}
]}
EOF
bash_res="$(bash -c '
  source "$1"
  cd "$2"
  (exit 42) || _cmux_auto_group
  rc=$?
  printf "rc=%s repo=%s\n" "$rc" "${_CMUX_LAST_GROUP_REPO:-}"
  cmux-autogroup-sync
  printf "sync_repo=%s\n" "${_CMUX_LAST_GROUP_REPO:-}"
' _ "$REPO_ROOT/init/cmux-autogroup.bash" "$REPO_B")"
assert_contains "Bash wrapper: preserves previous exit status 42" "rc=42" "$bash_res"
assert_contains "Bash wrapper: caches repo-b" "repo=$REPO_B" "$bash_res"
assert_contains "Bash wrapper: cmux-autogroup-sync works" "sync_repo=$REPO_B" "$bash_res"

# Zsh wrapper test (if zsh is installed)
if command -v zsh >/dev/null 2>&1; then
  reset_mock
  cat <<EOF > "$MOCK_LIST_FILE"
{"groups":[
  {"id":"G-B","anchor_workspace_id":"22222222-2222-2222-2222-222222222222","member_workspace_ids":["22222222-2222-2222-2222-222222222222"],"idempotency_key":"repo:$REPO_B","is_pinned":false}
]}
EOF
  zsh_res="$(zsh -c '
    source "$1"
    cd "$2"
    print -r -- "repo=${_CMUX_LAST_GROUP_REPO:-}"
    cmux-autogroup-sync
    print -r -- "sync_repo=${_CMUX_LAST_GROUP_REPO:-}"
  ' _ "$REPO_ROOT/cmux-autogroup.plugin.zsh" "$REPO_B")"
  assert_contains "Zsh wrapper: chpwd hook syncs repo-b" "repo=$REPO_B" "$zsh_res"
  assert_contains "Zsh wrapper: cmux-autogroup-sync works" "sync_repo=$REPO_B" "$zsh_res"
fi

# Fish wrapper test (if fish is installed)
if command -v fish >/dev/null 2>&1; then
  fish -n "$REPO_ROOT/init/cmux-autogroup.fish"
  reset_mock
  cat <<EOF > "$MOCK_LIST_FILE"
{"groups":[
  {"id":"G-B","anchor_workspace_id":"22222222-2222-2222-2222-222222222222","member_workspace_ids":["22222222-2222-2222-2222-222222222222"],"idempotency_key":"repo:$REPO_B","is_pinned":false}
]}
EOF
  fish_res="$(fish -c "
    source '$REPO_ROOT/init/cmux-autogroup.fish'
    cd '$REPO_B'
    echo repo=\$_CMUX_LAST_GROUP_REPO
    cmux-autogroup-sync
    echo sync_repo=\$_CMUX_LAST_GROUP_REPO
  ")"
  assert_contains "Fish wrapper: PWD hook syncs repo-b" "repo=$REPO_B" "$fish_res"
  assert_contains "Fish wrapper: cmux-autogroup-sync works" "sync_repo=$REPO_B" "$fish_res"
fi

if (( FAILURES > 0 )); then
  printf '%d test(s) failed.\n' "$FAILURES" >&2
  exit 1
fi
printf 'All tests passed!\n'
