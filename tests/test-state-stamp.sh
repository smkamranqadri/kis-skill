#!/usr/bin/env bash
# Guard: state-stamp.sh fingerprints the code outside kis/ and .orch/ so a fresh session can tell
# when State is behind the repo, and session-anchor.sh (and so the Antigravity wrapper) prints
# the one-line warning within its line budget.
set -euo pipefail
package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/kis" && pwd)"
S="$package_dir/scripts/state-stamp.sh"
H="$package_dir/hooks/session-anchor.sh"
A="$package_dir/hooks/antigravity-anchor.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
lines() { printf '%s\n' "$1" | wc -l | tr -d ' '; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.test
export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.test

g() { git -C "$repo" "$@"; }
# New repo "$repo" on branch main with one code file and a State file, committed.
new_repo() {
  rm -rf "${tmp:?}/${1:?}"; repo="$tmp/$1"; mkdir -p "$repo/kis/state" "$repo/src"
  git init -q -b main "$repo"
  printf 'print("hello from the fictional widget")\n' > "$repo/src/widget.txt"
  printf '# Current\n\n- Branch: main\n- Task: tune the widget\n- Next: ship it\n' > "$repo/kis/state/current.md"
  g add -A; g commit -q -m "initial"
}
# Replace the Stamp line in State with the helper's current output.
stamp() {
  grep -v '^Stamp:' "$repo/kis/state/current.md" > "$repo/kis/state/current.md.new" || true
  { "$S" "$repo"; cat "$repo/kis/state/current.md.new"; } > "$repo/kis/state/current.md"
  rm -f "$repo/kis/state/current.md.new"
}
check() { "$S" --check "$repo"; }
expect_quiet() { local out; out="$(check)"; [[ -z "$out" ]] || fail "$1: expected quiet, got: $out"; }
code_re='^Stale State: code outside kis/ changed since the last sync \([0-9a-f]+ on [A-Za-z0-9_-]+\); check State against the repo before trusting Task and Next\.$'
expect_code_stale() {
  local out; out="$(check)"
  [[ "$out" =~ $code_re ]] || fail "$1: expected the code reason, got: $out"
}

# Portable snapshot of a directory: every path, then every file's checksum and size.
gsnap() { find "$1" | LC_ALL=C sort; find "$1" -type f -print0 | LC_ALL=C sort -z | xargs -0 cksum; }
# Milliseconds from a monotonic-enough clock: EPOCHREALTIME where bash has it, else whole seconds.
now_ms() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local t="${EPOCHREALTIME/,/.}"; echo $(( ${t%.*} * 1000 + 10#${t#*.} / 1000 ))
  else echo $(( $(date +%s) * 1000 )); fi
}

# 1. Stamp shape.
new_repo shape
out="$("$S" "$repo")"
sha="$(g rev-parse --short HEAD)"
[[ "$out" =~ ^Stamp:\ main\ $sha\ [0-9a-f]{12}$ ]] || fail "stamp shape wrong: $out"

# 2. Match after stamping is quiet.
stamp; expect_quiet "match after stamping"

# 3. Branch differs.
g checkout -q -b feature
out="$(check)"
[[ "$out" == "Stale State: branch is feature, State was synced on main; check State against the repo before trusting Task and Next." ]] || fail "branch reason wrong: $out"
g checkout -q main

# 4. Code committed after the stamp is stale.
printf 'print("changed")\n' > "$repo/src/widget.txt"; g add -A; g commit -q -m "change code"
expect_code_stale "code committed after stamp"

# 5. A kis/-only commit after the stamp is quiet.
new_repo kisonly; stamp; g add -A; g commit -q -m "stamp"
printf -- '- Proof: nothing yet\n' >> "$repo/kis/state/current.md"; g add -A; g commit -q -m "kis only"
expect_quiet "kis-only commit"

# 6. Code and State committed together right after the stamp (sync, then commit): quiet.
new_repo together
printf 'print("new feature")\n' > "$repo/src/widget.txt"
stamp; g add -A; g commit -q -m "code and state"
expect_quiet "code and State committed together"

# 7. Uncommitted edit, and a new untracked file, outside kis/ after the stamp.
new_repo dirty; stamp; expect_quiet "dirty baseline"
printf 'print("edited")\n' >> "$repo/src/widget.txt"
expect_code_stale "uncommitted edit"
g checkout -q -- src/widget.txt; expect_quiet "edit reverted"
printf 'extra\n' > "$repo/src/extra.txt"
expect_code_stale "untracked file"

# 8. An uncommitted edit that existed when stamped, unchanged: quiet.
new_repo predirty
printf 'print("work in progress")\n' >> "$repo/src/widget.txt"; printf 'new\n' > "$repo/src/wip.txt"
stamp; expect_quiet "pre-existing uncommitted edits"
g add -A; g commit -q -m "wip"; expect_quiet "pre-existing edits then committed"

# 9. Edits only under kis/ or .orch/ are quiet.
new_repo excluded; stamp
printf 'notes\n' >> "$repo/kis/state/current.md"; mkdir -p "$repo/kis/knowledge" "$repo/.orch"
printf 'fact\n' > "$repo/kis/knowledge/fact.md"; printf 'log\n' > "$repo/.orch/log.txt"
expect_quiet "kis and .orch edits"

# 10. Ignored files are quiet.
new_repo ignored; printf 'build/\n*.log\n' > "$repo/.gitignore"; g add -A; g commit -q -m "ignore"; stamp
mkdir -p "$repo/build"; printf 'artifact\n' > "$repo/build/out.bin"; printf 'noise\n' > "$repo/run.log"
expect_quiet "ignored files"

# 11. No Stamp line, not a git repo, no State: quiet, exit 0.
new_repo legacy
out="$("$S" --check "$repo")"; [[ -z "$out" ]] || fail "legacy State should be quiet: $out"
mkdir -p "$tmp/plain/kis/state"; printf -- '- Stamp: main abc1234 0123456789ab\n' > "$tmp/plain/kis/state/current.md"
"$S" --check "$tmp/plain" >"$tmp/plain.out" || fail "non-git --check exited non-zero"
[[ ! -s "$tmp/plain.out" ]] || fail "non-git should be quiet"
new_repo nostate; rm -rf "$repo/kis"
"$S" --check "$repo" >"$tmp/nostate.out" || fail "no-State --check exited non-zero"
[[ ! -s "$tmp/nostate.out" ]] || fail "no-State should be quiet"

# 12. A bullet marker and a non-current.md State file are read too.
new_repo bullet; mv "$repo/kis/state/current.md" "$repo/kis/state/status.md"
{ printf -- '- '; "$S" "$repo"; cat "$repo/kis/state/status.md"; } > "$repo/kis/state/status.new"; mv "$repo/kis/state/status.new" "$repo/kis/state/status.md"
expect_quiet "bulleted Stamp in status.md"
printf 'more\n' >> "$repo/src/widget.txt"; expect_code_stale "bulleted Stamp in status.md"

# 13. Detached HEAD and no commits yet.
new_repo detached; g checkout -q --detach
out="$("$S" "$repo")"; [[ "$out" =~ ^Stamp:\ detached\ [0-9a-f]+\ [0-9a-f]{12}$ ]] || fail "detached stamp: $out"
repo="$tmp/unborn"; mkdir -p "$repo/kis/state"; git init -q -b main "$repo"; printf 'x\n' > "$repo/a.txt"
out="$("$S" "$repo")"; [[ "$out" =~ ^Stamp:\ main\ none\ [0-9a-f]{12}$ ]] || fail "unborn stamp: $out"

# 14. Linked worktree: stamping and checking work, and the real index is not touched.
new_repo main-wt
wt="$tmp/linked-wt"; g worktree add -q -b side "$wt"
repo="$wt"
idx="$(git -C "$wt" rev-parse --absolute-git-dir)/index"
[[ -f "$idx" ]] || fail "linked worktree index not found: $idx"
cp "$idx" "$tmp/index.before"
printf 'tracked change\n' >> "$wt/src/widget.txt"; printf 'new\n' > "$wt/src/loose.txt"
stamp; expect_quiet "linked worktree match"
cmp "$idx" "$tmp/index.before" || fail "linked worktree index changed by stamping or checking"
printf 'later\n' >> "$wt/src/widget.txt"; expect_code_stale "linked worktree edit"
cmp "$idx" "$tmp/index.before" || fail "linked worktree index changed by the check"
main_idx="$tmp/main-wt/.git/index"; cp "$main_idx" "$tmp/main-index.before"
"$S" "$tmp/main-wt" >/dev/null; "$S" --check "$tmp/main-wt" >/dev/null
cmp "$main_idx" "$tmp/main-index.before" || fail "main worktree index changed"

# 14b. Side-effect free: stamping and checking write nothing under .git (no objects, no index, no
#      locks), even with a large untracked file under .orch/, an untracked file outside kis/ and a
#      modified tracked file.
new_repo pure
mkdir -p "$repo/.orch"
head -c 3000000 /dev/zero | tr '\0' 'q' > "$repo/.orch/big.bin"
printf 'fresh\n' > "$repo/src/untracked.txt"
printf 'modified\n' >> "$repo/src/widget.txt"
gd="$(git -C "$repo" rev-parse --absolute-git-dir)"
snap() { gsnap "$gd"; git -C "$repo" count-objects -v; find "$gd/objects" -type f | wc -l | tr -d ' '; }
snap > "$tmp/git.before"; cp "$gd/index" "$tmp/pure.index.before"
stamp
snap_after_stamp="$(snap)"
# stamp() rewrote State only (outside .git); the .git snapshot must still match.
cmp "$tmp/git.before" <(printf '%s\n' "$snap_after_stamp") || fail "stamp mode changed something under .git"
expect_quiet "pure repo match"
snap > "$tmp/git.after"
cmp "$tmp/git.before" "$tmp/git.after" || fail "--check changed something under .git"
cmp "$gd/index" "$tmp/pure.index.before" || fail "real index changed"
[[ -z "$(find "$gd" -name '*.lock')" ]] || fail "a lock file was left under .git"
[[ "$(git -C "$repo" count-objects -v | grep -c '^count: ')" == "1" ]] || fail "count-objects output unexpected"
printf 'again\n' >> "$repo/src/untracked.txt"; expect_code_stale "pure repo edit"
snap > "$tmp/git.after"; cmp "$tmp/git.before" "$tmp/git.after" || fail "stale --check changed something under .git"

# 15. Full cycle through the anchor: stamp, commit everything, fresh anchor call is clean; then
#     a code change makes the anchor print the stale line and still fit the budget.
budget=20
export KIS_ANCHOR_MAX_LINES="$budget"
new_repo cycle
printf 'print("cycle work")\n' > "$repo/src/widget.txt"
stamp; stamped_sha="$(g rev-parse --short HEAD)"; g add -A; g commit -q -m "work and sync"
out="$("$H" "$repo")"
printf '%s\n' "$out" | grep -q '^Stale State:' && fail "fresh anchor should not warn: $out"
printf 'print("moved on")\n' > "$repo/src/widget.txt"
out="$("$H" "$repo")"
stale="Stale State: code outside kis/ changed since the last sync ($stamped_sha on main); check State against the repo before trusting Task and Next."
[[ "$(printf '%s\n' "$out" | grep -c '^Stale State:')" == "1" ]] || fail "anchor should print exactly one stale line: $out"
printf '%s\n' "$out" | grep -qxF "$stale" || fail "anchor stale line wrong: $out"
# It follows the State heading block and precedes the summary.
n_head="$(printf '%s\n' "$out" | grep -n '^## Current State: ' | cut -d: -f1)"
n_stale="$(printf '%s\n' "$out" | grep -n '^Stale State:' | cut -d: -f1)"
n_sum="$(printf '%s\n' "$out" | grep -n '^Branch: ' | cut -d: -f1)"
(( n_stale == n_head + 2 && n_stale < n_sum )) || fail "stale line misplaced: heading $n_head stale $n_stale summary $n_sum"
(( $(lines "$out") <= budget )) || fail "stale anchor over budget: $(lines "$out")"
# Tightest budget, with a second State file and a State that has no summary fields.
out="$(KIS_ANCHOR_MAX_LINES=17 "$H" "$repo")"
(( $(lines "$out") <= 17 )) || fail "stale anchor over a 17-line budget: $(lines "$out")"
out="$(KIS_ANCHOR_MAX_LINES=5 "$H" "$repo")"
(( $(lines "$out") <= 17 )) || fail "budget below the minimum not clamped to 17: $(lines "$out")"
printf 'other\n' > "$repo/kis/state/other.md"
out="$(KIS_ANCHOR_MAX_LINES=17 "$H" "$repo")"
(( $(lines "$out") <= 17 )) || fail "stale anchor with a second State file over 17: $(lines "$out")"
printf 'Stamp: main %s aaaaaaaaaaaa\nprose only\n' "$(g rev-parse --short HEAD)" > "$repo/kis/state/current.md"
out="$(KIS_ANCHOR_MAX_LINES=17 "$H" "$repo")"
printf '%s\n' "$out" | grep -q '^Stale State:' || fail "stale line missing with a summary-less State: $out"
(( $(lines "$out") <= 17 )) || fail "stale anchor with a summary-less State over 17: $(lines "$out")"

# 16. The Antigravity wrapper carries the stale line.
if command -v ruby >/dev/null 2>&1; then
  new_repo agy
  stamp
  printf 'print("after sync")\n' >> "$repo/src/widget.txt"
  markers="$tmp/markers"; mkdir -p "$markers"
  payload="{\"conversationId\":\"conv-state-stamp\",\"workspacePaths\":[\"$repo\"]}"
  ag_out="$(printf '%s' "$payload" | TMPDIR="$markers" "$A")"
  [[ "$ag_out" == *'Stale State: code outside kis/ changed since the last sync'* ]] || fail "Antigravity anchor missing the stale line: $ag_out"
  new_repo agyclean
  stamp
  payload="{\"conversationId\":\"conv-state-stamp-clean\",\"workspacePaths\":[\"$repo\"]}"
  ag_out="$(printf '%s' "$payload" | TMPDIR="$markers" "$A")"
  [[ "$ag_out" == *'"injectSteps"'* && "$ag_out" != *'Stale State'* ]] || fail "clean Antigravity anchor should not warn: $ag_out"
else
  echo "(ruby absent: Antigravity wrapper not exercised)"
fi

# 18. A deleted tracked file is a change; deleting it and committing right after the sync is not.
new_repo deleted; stamp; expect_quiet "deletion baseline"
rm -f "${repo:?}/src/widget.txt"; expect_code_stale "tracked file deleted"
g checkout -q -- src/widget.txt; expect_quiet "deletion reverted"
new_repo deletedsync; rm -f "${repo:?}/src/widget.txt"; stamp; expect_quiet "deletion present at sync"
g add -A; g commit -q -m "delete"; expect_quiet "deletion committed after sync"

# 19. Symlinks: retargeting one is a change, and a symlink present at sync then committed is not.
new_repo links; ln -s widget.txt "$repo/src/link"; g add -A; g commit -q -m "link"; stamp; expect_quiet "symlink baseline"
ln -sfn extra.txt "$repo/src/link"; expect_code_stale "symlink retargeted"
ln -sfn widget.txt "$repo/src/link"; expect_quiet "symlink restored"
new_repo linksync; ln -s nowhere "$repo/src/dangling"; stamp; expect_quiet "dangling symlink at sync"
g add -A; g commit -q -m "dangling"; expect_quiet "dangling symlink committed after sync"

# 20. The exec bit is part of the fingerprint, and honoured at sync time only when git honours it.
new_repo modebit; stamp; chmod +x "$repo/src/widget.txt"; expect_code_stale "chmod +x"
chmod -x "$repo/src/widget.txt"; expect_quiet "chmod reverted"
new_repo modesync; printf '#!/bin/sh\n' > "$repo/run.sh"; chmod +x "$repo/run.sh"; stamp
g add -A; g commit -q -m "script"; expect_quiet "executable script committed after sync"
new_repo nomode; g config core.fileMode false; printf '#!/bin/sh\n' > "$repo/run.sh"; chmod +x "$repo/run.sh"; chmod +x "$repo/src/widget.txt"
stamp; g add -A; g commit -q -m "script and chmod"
[[ "$(g ls-files -s run.sh | cut -d' ' -f1)" == "100644" ]] || fail "core.fileMode=false fixture: run.sh not committed as 100644"
expect_quiet "core.fileMode=false: exec bits at sync then committed"

# 21. A project that is a subdirectory of a repository fingerprints only its own subtree.
repo="$tmp/mono"; mkdir -p "$repo/app/kis/state" "$repo/app/src" "$repo/other/kis"; git init -q -b main "$repo"
printf 'a\n' > "$repo/app/src/a.txt"; printf 'o\n' > "$repo/other/o.txt"; printf '# Current\n' > "$repo/app/kis/state/current.md"
g add -A; g commit -q -m "mono"
app="$repo/app"
{ "$S" "$app"; cat "$app/kis/state/current.md"; } > "$app/kis/state/current.new"; mv "$app/kis/state/current.new" "$app/kis/state/current.md"
appcheck() { "$S" --check "$app"; }
[[ -z "$(appcheck)" ]] || fail "monorepo baseline not quiet"
printf 'note\n' >> "$app/kis/state/current.md"; mkdir -p "$app/kis/knowledge"; printf 'f\n' > "$app/kis/knowledge/f.md"
[[ -z "$(appcheck)" ]] || fail "an edit under the project's own kis/ must be quiet: $(appcheck)"
printf 'o2\n' >> "$repo/other/o.txt"; printf 'n\n' > "$repo/other/new.txt"; printf 'k\n' > "$repo/other/kis/k.md"
[[ -z "$(appcheck)" ]] || fail "a sibling project's change must be quiet: $(appcheck)"
mkdir -p "$repo/kis"; printf 'z\n' > "$repo/kis/rootkis"; printf 'r\n' > "$repo/root.txt"
[[ -z "$(appcheck)" ]] || fail "a change outside the project's subtree must be quiet: $(appcheck)"
printf 'a2\n' >> "$app/src/a.txt"
[[ "$(appcheck)" =~ $code_re ]] || fail "an edit inside the project's subtree must be stale: $(appcheck)"

# 22. Paths with a tab, a newline, a quote, a backslash or a trailing CR are fingerprinted like any other.
for name in $'tab\tname' $'new\nline' '"quoted"' 'back\slash' $'cr\r' $'ctl\001byte'; do
  new_repo odd; printf 'one\n' > "$repo/$name"; g add -A; g commit -q -m "odd path"
  printf 'two\n' > "$repo/$name"; stamp; expect_quiet "odd tracked path at sync"
  printf 'three\n' > "$repo/$name"; expect_code_stale "odd tracked path edited after sync"
  new_repo oddnew; printf 'one\n' > "$repo/$name"; stamp; g add -A; g commit -q -m "odd path"
  expect_quiet "odd untracked path at sync then committed"
  rm -f "${repo:?}/$name"; expect_code_stale "odd tracked path deleted"
done
new_repo oddtab; printf 'one\n' > "$repo/$(printf 'x\ty')"; g add -A; g commit -q -m "tab"
printf 'three\n' > "$repo/$(printf 'x\ty')"; first="$("$S" "$repo")"
printf 'four\n' > "$repo/$(printf 'x\ty')"; [[ "$("$S" "$repo")" != "$first" ]] || fail "an edit to a tab-named file did not change the stamp"

# 23. A submodule counts by its commit: a new commit inside it is a change, and bumping it after
#     the sync is not.
new_repo subsrc; subsrc="$repo"
new_repo withsub
g -c protocol.file.allow=always submodule add -q "$subsrc" sub >/dev/null 2>&1; g commit -q -m "add submodule"
stamp; expect_quiet "submodule baseline"
printf 'more\n' > "$repo/sub/more.txt"; git -C "$repo/sub" add more.txt; git -C "$repo/sub" commit -q -m "advance"
expect_code_stale "new commit inside a submodule"
stamp; expect_quiet "submodule bump at sync"
g add sub; g commit -q -m "bump submodule"; expect_quiet "submodule bump committed after sync"

# 24. No filter program ever runs, and nothing is written under .git: a dummy clean/process driver
#     would write a marker; Git LFS would copy objects into .git/lfs.
filter_case() {  # <label>: the repo is set up; modify and check, then compare .git and the marker
  gd="$(git -C "$repo" rev-parse --absolute-git-dir)"
  stamp; expect_quiet "$1 baseline"
  gsnap "$gd" > "$tmp/filter.before"
  printf 'edited\n' >> "$repo/src/data.dat"; head -c 20000 /dev/urandom > "$repo/src/fresh.dat"
  touch -t 202001010000 "$repo/src/touched.dat"
  expect_code_stale "$1 edit"; "$S" "$repo" >/dev/null; "$S" --check "$repo" >/dev/null
  gsnap "$gd" > "$tmp/filter.after"
  cmp "$tmp/filter.before" "$tmp/filter.after" || fail "$1: something changed under .git"
  [[ ! -e "$tmp/filter.marker" ]] || fail "$1: a filter program ran"
}
new_repo filtered
printf 'one\n' > "$repo/src/data.dat"; printf 'two\n' > "$repo/src/touched.dat"; printf '*.dat filter=probe\n' > "$repo/.gitattributes"
g add -A; g commit -q -m "dat files"
printf '#!/bin/sh\necho ran >> "%s"\ncat\n' "$tmp/filter.marker" > "$tmp/filter.sh"; chmod +x "$tmp/filter.sh"
g config filter.probe.clean "$tmp/filter.sh"; g config filter.probe.smudge "$tmp/filter.sh"
g config filter.probe.process "$tmp/filter.sh"; g config filter.probe.required true
filter_case "dummy filter driver"
if git lfs version >/dev/null 2>&1; then
  new_repo lfs
  git -C "$repo" lfs install --local >/dev/null 2>&1; git -C "$repo" lfs track '*.dat' >/dev/null 2>&1
  printf 'one\n' > "$repo/src/data.dat"; printf 'two\n' > "$repo/src/touched.dat"
  g add -A; g commit -q -m "lfs files"
  filter_case "Git LFS"
else
  echo "(git lfs absent: LFS case skipped)"
fi

# 25. Reads never write: every git call the fingerprint makes carries GIT_OPTIONAL_LOCKS=0.
new_repo locks
shim="$tmp/lockshim"; mkdir -p "$shim"; real_git="$(command -v git)"
printf '#!/bin/sh\nprintf "%%s\\n" "${GIT_OPTIONAL_LOCKS-unset}" >> "%s"\nexec "%s" "$@"\n' "$tmp/locks.log" "$real_git" > "$shim/git"; chmod +x "$shim/git"
stamp
PATH="$shim:$PATH" "$S" "$repo" >/dev/null; PATH="$shim:$PATH" "$S" --check "$repo" >/dev/null
[[ -s "$tmp/locks.log" ]] || fail "lock shim saw no git call"
[[ -z "$(grep -vx '0' "$tmp/locks.log")" ]] || fail "a git call ran without GIT_OPTIONAL_LOCKS=0"

# 26. The project root defaults to the install's project, so the cwd does not matter (sync stamps
#     from wherever the agent stands); outside an install it is the cwd.
new_repo instproj
mkdir -p "$repo/.agents/skills"; cp -R "$package_dir" "$repo/.agents/skills/kis"
IS="$repo/.agents/skills/kis/scripts/state-stamp.sh"
from_root="$(cd "$repo" && "$IS")"; from_sub="$(cd "$repo/src" && "$IS")"
[[ "$from_root" == "$from_sub" ]] || fail "stamp depends on the cwd: '$from_root' vs '$from_sub'"
{ printf '%s\n' "$from_sub"; cat "$repo/kis/state/current.md"; } > "$repo/kis/state/current.new"; mv "$repo/kis/state/current.new" "$repo/kis/state/current.md"
[[ -z "$("$S" --check "$repo")" ]] || fail "a stamp written from a subdirectory is stale from the root"
[[ -z "$(cd "$repo/src" && "$IS" --check)" ]] || fail "--check with no argument from a subdirectory is not quiet"
printf 'later\n' >> "$repo/src/widget.txt"
[[ "$(cd "$repo/src" && "$IS" --check)" =~ $code_re ]] || fail "--check with no argument from a subdirectory missed an edit"
[[ "$(cd "$repo/src" && "$S")" != "$("$S" "$repo")" ]] || fail "outside an install the root must default to the cwd"

# 27. The Stamp line is read through markdown: a bold label and a backticked value still count.
for form in 'Stamp: %s' '- Stamp: %s' '* Stamp: %s' '- **Stamp:** %s' '**Stamp:** %s' '- Stamp: `%s`'; do
  new_repo marked; value="$("$S" "$repo" | sed 's/^Stamp: //')"
  # shellcheck disable=SC2059
  printf -- "$form\n" "$value" > "$repo/kis/state/current.md"
  expect_quiet "Stamp line '$form'"
  printf 'edit\n' >> "$repo/src/widget.txt"; expect_code_stale "Stamp line '$form'"
done

# 28. A huge untracked tree stays fast, and the time cap holds with or without `timeout`.
new_repo big; stamp
mkdir "$repo/vendored"; (cd "$repo/vendored" && seq 1 20000 | xargs touch)
t0="$(now_ms)"; out="$(check)"; t1="$(now_ms)"
[[ "$out" =~ $code_re ]] || fail "20k untracked files: expected the stale line, got: $out"
elapsed=$(( t1 - t0 )); echo "(20000 untracked files: --check took ${elapsed} ms)"
(( elapsed < 2000 )) || fail "20k untracked files: --check took ${elapsed} ms, over the 2000 ms budget"
t0="$(now_ms)"; "$S" "$repo" >/dev/null; t1="$(now_ms)"
echo "(20000 untracked files: stamp took $(( t1 - t0 )) ms)"
(( t1 - t0 < 2000 )) || fail "20k untracked files: stamp took $(( t1 - t0 )) ms"

slow="$tmp/slowbin"; mkdir -p "$slow"
printf '#!/bin/sh\ncase " $* " in *" ls-files "*) sleep 30 ;; esac\nexec "%s" "$@"\n' "$(command -v git)" > "$slow/git"; chmod +x "$slow/git"
nopath="$tmp/nobin"; mkdir -p "$nopath"
for tool in bash sh env tr grep sed awk sort paste mktemp rm dirname basename cat find head readlink sleep cut wc xargs mkdir uname date kill; do
  src="$(command -v "$tool" 2>/dev/null || true)"
  if [[ -n "$src" && -x "$src" && ! -e "$nopath/$tool" ]]; then ln -s "$src" "$nopath/$tool"; fi
done
cap_case() {  # <label> <PATH>
  new_repo capped; stamp
  local t0 t1 rc=0
  t0="$(now_ms)"; out="$(PATH="$2" KIS_STAMP_TIMEOUT_SECONDS=1 "$S" --check "$repo")"; t1="$(now_ms)"
  [[ -z "$out" ]] || fail "$1: a --check past the time cap must be quiet: $out"
  (( t1 - t0 < 6000 )) || fail "$1: --check took $(( t1 - t0 )) ms with a 1 s cap"
  t0="$(now_ms)"; PATH="$2" KIS_STAMP_TIMEOUT_SECONDS=1 "$S" "$repo" >/dev/null 2>&1 || rc=$?
  t1="$(now_ms)"
  [[ "$rc" == 1 ]] || fail "$1: a stamp past the time cap must exit 1, got $rc"
  (( t1 - t0 < 6000 )) || fail "$1: stamp took $(( t1 - t0 )) ms with a 1 s cap"
}
cap_case "time cap" "$slow:$PATH"
ln -s "$slow/git" "$nopath/git"
[[ ! -e "$nopath/timeout" ]] || fail "fixture: timeout must be absent from the bare PATH"
cap_case "time cap without timeout" "$nopath"
# The cap's own noise: a capped stamp prints its one error line and nothing else (no bash job notice).
new_repo capnoise; stamp
for label_path in "with timeout|$slow:$PATH" "without timeout|$nopath"; do
  err="$(PATH="${label_path#*|}" KIS_STAMP_TIMEOUT_SECONDS=1 "$S" "$repo" 2>&1 >/dev/null || true)"
  [[ "$err" =~ ^Error:\ cannot\ compute\ a\ stamp[^$'\n']*$ ]] || fail "a capped stamp ${label_path%%|*} printed more than its error line: $err"
done
# Without `timeout`, a run that finishes under the cap leaves no watcher or sleep behind.
real_bin="$tmp/realbin"; mkdir -p "$real_bin"; cp -P "$nopath"/* "$real_bin"/; rm -f "$real_bin/git"; ln -s "$(command -v git)" "$real_bin/git"
new_repo leftover; stamp
KIS_STAMP_TIMEOUT_SECONDS=4747 PATH="$real_bin" "$S" --check "$repo" >/dev/null
KIS_STAMP_TIMEOUT_SECONDS=4747 PATH="$real_bin" "$S" "$repo" >/dev/null
sleep 0.3
if ps -e -o args= 2>/dev/null | grep -qx 'sleep 4747'; then
  pkill -f '^sleep 4747$' 2>/dev/null || true
  fail "a run without timeout left its watcher's sleep behind"
fi
# And with no git at all the check stays quiet and a stamp fails cleanly.
rm -f "${nopath:?}/git"
new_repo nogit; stamp
out="$(PATH="$nopath" "$S" --check "$repo")"; [[ -z "$out" ]] || fail "no git on PATH: --check must be quiet: $out"
rc=0; PATH="$nopath" "$S" "$repo" >/dev/null 2>&1 || rc=$?; [[ "$rc" == 1 ]] || fail "no git on PATH: stamp must exit 1, got $rc"

# 29. Thousands of untracked symlinks hash in one batch, with the same fingerprint as per-file.
new_repo manylinks; stamp
mkdir "$repo/links"; (cd "$repo/links" && seq 1 5000 | sed 's/.*/ln -s ..\/src\/widget.txt l&/' | sh)
t0="$(now_ms)"; out="$(check)"; t1="$(now_ms)"
[[ "$out" =~ $code_re ]] || fail "5000 untracked symlinks: expected the stale line, got: $out"
echo "(5000 untracked symlinks: --check took $(( t1 - t0 )) ms)"
(( t1 - t0 < 2000 )) || fail "5000 untracked symlinks: --check took $(( t1 - t0 )) ms, over the 2000 ms budget"
stamp; g add -A; g commit -q -m "links"; expect_quiet "5000 symlinks present at sync, then committed"
ln -sfn extra.txt "$repo/links/l77"; expect_code_stale "one of 5000 symlinks retargeted"
# A link target with a newline breaks the batch's line count; the slow route must still match git.
new_repo nllink; ln -s $'two\nlines' "$repo/src/nl"; stamp; g add -A; g commit -q -m "newline target"
expect_quiet "newline-target symlink present at sync, then committed"
ln -sfn $'two\nlinez' "$repo/src/nl"; expect_code_stale "newline-target symlink retargeted"

# 30. A name with a byte >= 0x80 (macOS reports NFC, find prints NFD) is classified by bash builtins and
#     joins the batched hash, with no git call per file. macOS itself was not run: the routing is
#     observed through a git shim that logs each call.
new_repo nonascii; printf 'one\n' > "$repo/caf$(printf '\303\251').txt"; g add -A; g commit -q -m "cafe"
stamp; expect_quiet "non-ASCII tracked name at sync"
printf 'two\n' > "$repo/caf$(printf '\303\251').txt"; expect_code_stale "non-ASCII tracked name edited"
new_repo nonasciinew; printf 'one\n' > "$repo/caf$(printf 'e\314\201').txt"; stamp; g add -A; g commit -q -m "cafe nfd"
expect_quiet "non-ASCII untracked name at sync, then committed"
printf 'two\n' > "$repo/caf$(printf '\303\251').txt"
route_shim="$tmp/routeshim"; mkdir -p "$route_shim"; : > "$tmp/route.log"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$tmp/route.log" "$(command -v git)" > "$route_shim/git"; chmod +x "$route_shim/git"
PATH="$route_shim:$PATH" "$S" "$repo" >/dev/null
! grep -q 'hash-object -- caf' "$tmp/route.log" || fail "a non-ASCII name forked a git hash-object of its own"
grep -q 'hash-object --stdin-paths' "$tmp/route.log" || fail "a non-ASCII name did not join the batched hash"
# Every kind of entry under a non-ASCII directory fingerprints like the old per-file route did.
new_repo nonasciikinds; d="$repo/caf$(printf '\303\251')"; mkdir -p "$d/sub"
printf 'a\n' > "$d/plain.txt"; printf '#!/bin/sh\n' > "$d/run.sh"; chmod +x "$d/run.sh"; printf 'g\n' > "$d/gone.txt"
ln -s plain.txt "$d/link"; ln -s nowhere "$d/dangling"; printf 'n\n' > "$d/sub/n.txt"
mkdir "$d/sub2"; printf 's\n' > "$d/sub2/s.txt"
g add -A; g commit -q -m "kinds"
chmod +x "$d/plain.txt"; ln -s sub2 "$d/dirlink"
rm "$d/gone.txt"; printf 'b\n' > "$d/plain.txt"; ln -sfn run.sh "$d/link"; printf 'u\n' > "$d/untracked.txt"; rm -rf "$d/sub"; ln -s x "$d/sub"
ref_dir="$tmp/ref-stamp"; mkdir -p "$ref_dir"
if git -C "$package_dir/../.." show b48136a:skills/kis/scripts/state-stamp.sh > "$ref_dir/state-stamp.sh" 2>/dev/null; then
  [[ "$(bash "$ref_dir/state-stamp.sh" --compute "$repo" 2>/dev/null)" == "$("$S" --compute "$repo")" ]] || fail "non-ASCII directory with every entry kind: fingerprint differs from the per-file route"
else
  echo "(reference script b48136a not in this checkout: the per-file comparison was not run)"
fi
# Direct assertions, no reference script: an exec-bit change and a new symlink to a directory, both
# under a non-ASCII directory, are real changes.
new_repo nonasciidirect; d="$repo/caf$(printf '\303\251')"; mkdir -p "$d/sub2"
printf 'a\n' > "$d/plain.txt"; printf 's\n' > "$d/sub2/s.txt"; g add -A; g commit -q -m "direct"; stamp
expect_quiet "non-ASCII directory at sync"
chmod +x "$d/plain.txt"; expect_code_stale "chmod +x of a committed non-ASCII-directory file"
chmod -x "$d/plain.txt"; expect_quiet "exec bit restored"
ln -s sub2 "$d/dirlink"; expect_code_stale "new symlink to a directory under a non-ASCII directory"
# 2000 files under a non-ASCII directory must not cost a fork each (the 5 s --check cap would drop the line).
new_repo nonasciimany; stamp
mkdir "$repo/caf$(printf '\303\251')"; (cd "$repo/caf$(printf '\303\251')" && seq 1 2000 | sed 's/.*/echo & > f&.txt/' | sh)
t0="$(now_ms)"; out="$(check)"; t1="$(now_ms)"
[[ "$out" =~ $code_re ]] || fail "2000 files under a non-ASCII directory: expected the stale line, got: $out"
echo "(2000 files under a non-ASCII directory: --check took $(( t1 - t0 )) ms)"
(( t1 - t0 < 2000 )) || fail "2000 files under a non-ASCII directory: --check took $(( t1 - t0 )) ms, over the 2000 ms budget"
stamp; g add -A; g commit -q -m "many"; expect_quiet "2000 non-ASCII files present at sync, then committed"
printf 'x\n' > "$repo/caf$(printf '\303\251')/f77.txt"; expect_code_stale "one of 2000 non-ASCII files edited"

# 31. A real control byte in a name does not collide with the encoding of a newline.
new_repo ctl; printf 'one\n' > "$repo/$(printf 'x\001y')"; printf 'two\n' > "$repo/$(printf 'x\ny')"; g add -A; g commit -q -m "ctl and newline"
stamp; expect_quiet "control-byte and newline names at sync"
printf 'three\n' > "$repo/$(printf 'x\001y')"; expect_code_stale "control-byte name edited next to a newline name"
printf 'one\n' > "$repo/$(printf 'x\001y')"; expect_quiet "control-byte name restored"
printf 'three\n' > "$repo/$(printf 'x\ny')"; expect_code_stale "newline name edited next to a control-byte name"

# 32. Run through the .claude/skills/kis link the installer creates, the root is still the project.
new_repo linkproj
mkdir -p "$repo/.agents/skills" "$repo/.claude/skills"; cp -R "$package_dir" "$repo/.agents/skills/kis"
ln -s ../../.agents/skills/kis "$repo/.claude/skills/kis"
via_agents="$(cd "$repo/src" && "$repo/.agents/skills/kis/scripts/state-stamp.sh")"
via_link="$(cd "$repo/src" && "$repo/.claude/skills/kis/scripts/state-stamp.sh")"
[[ "$via_agents" == "$via_link" ]] || fail "the .claude link gives another stamp: '$via_agents' vs '$via_link'"
# A package that is itself a symlink to another place keeps working through the logical path.
new_repo linkpkg; cp -R "$package_dir" "$tmp/pkgsrc-$$"; mkdir -p "$repo/.agents/skills"; ln -s "$tmp/pkgsrc-$$" "$repo/.agents/skills/kis"
[[ "$(cd "$repo/src" && "$repo/.agents/skills/kis/scripts/state-stamp.sh")" == "$("$S" "$repo")" ]] || fail "a symlinked package lost its project root"
# With no argument and a working directory outside any repository, only the logical path
# (.agents/...) can name the project, so a physical-first resolution fails here.
[[ "$(cd "$tmp" && "$repo/.agents/skills/kis/scripts/state-stamp.sh")" == "$("$S" "$repo")" ]] || fail "a symlinked package did not resolve its project through the logical path"

# 17. The helper ships executable with the hooks: committed as 100755 and executable after a real
#     install of the package.
repo_root="$(cd "$package_dir/../.." && pwd)"
if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mode="$(git -C "$repo_root" ls-files -s -- skills/kis/scripts/state-stamp.sh | cut -d' ' -f1)"
  [[ -z "$mode" || "$mode" == "100755" ]] || fail "state-stamp.sh is tracked as $mode, not 100755"
fi
install_target="$tmp/installed"; mkdir -p "$install_target"
"$repo_root/scripts/install-skill.sh" --source "$repo_root" --target "$install_target" --no-commands --no-anchor >/dev/null 2>&1
[[ -x "$install_target/.agents/skills/kis/scripts/state-stamp.sh" ]] || fail "installed state-stamp.sh is not executable"
[[ -x "$install_target/.agents/skills/kis/hooks/session-anchor.sh" ]] || fail "installed session-anchor.sh is not executable"

echo "state-stamp tests: pass"
