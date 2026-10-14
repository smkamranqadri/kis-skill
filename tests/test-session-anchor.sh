#!/usr/bin/env bash
# Guard: the KIS SessionStart anchor prints a short summary (Branch, Task, Blocker, Next) with a
# pointer to State, within its stated line budget. It never dumps the whole State file, and it
# reads Blocker/Next from `## Open` / `## Next` when the bullet labels are absent.
set -euo pipefail
package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/kis" && pwd)"
H="$package_dir/hooks/session-anchor.sh"
A="$package_dir/hooks/antigravity-anchor.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
budget=20
export KIS_ANCHOR_MAX_LINES="$budget"
fail() { echo "FAIL: $*" >&2; exit 1; }
lines() { printf '%s\n' "$1" | wc -l | tr -d ' '; }

# 1. Labelled State, about 80 lines, with a continuation that only appears on the second line.
root="$tmp/labelled"; mkdir -p "$root/kis/state"
{
  echo "# Current"; echo
  echo "- Branch: main, tracking origin/main."
  echo "- Task: ship the compact reader. The continuation carries extra wording"
  echo "  that only appears on the second line of the Task field."
  echo "- Blocker: none."
  echo "- Next: run the suite."
  echo "- Proof: recorded elsewhere."
  echo
  echo "Body line that must not reach the anchor."
  i=0; while (( i < 70 )); do echo "- filler line $i"; i=$((i + 1)); done
  echo "SENTINEL-BODY-ONLY"
} > "$root/kis/state/current.md"
out="$("$H" "$root")"
[[ "$out" == *"Branch: main, tracking origin/main."* ]] || fail "Branch missing"
[[ "$out" == *"Task: ship the compact reader."*"that only appears on the second line"* ]] || fail "Task continuation not joined: $out"
[[ "$out" == *"Blocker: none."* ]] || fail "Blocker missing"
[[ "$out" == *"Next: run the suite."* ]] || fail "Next missing"
[[ "$out" != *"SENTINEL-BODY-ONLY"* ]] || fail "anchor dumped the State body"
[[ "$out" != *"filler line"* ]] || fail "anchor dumped State filler"
[[ "$out" == *"Full State: kis/state/current.md"*"lines"* ]] || fail "pointer missing"
[[ "$out" == *"/kis:start"* ]] || fail "command list missing"
(( $(lines "$out") <= budget )) || fail "labelled anchor over budget: $(lines "$out") lines"

# 2. A State without a Blocker label still prints the other three, and invents nothing.
root="$tmp/noblocker"; mkdir -p "$root/kis/state"
printf -- '- Branch: main\n- Task: do the thing\n- Next: go\n' > "$root/kis/state/current.md"
out="$("$H" "$root")"
for f in "Branch: main" "Task: do the thing" "Next: go"; do
  [[ "$out" == *"$f"* ]] || fail "missing: $f"
done
[[ "$out" != *"Blocker:"* ]] || fail "invented a Blocker"

# 3. Label-less next/open: Blocker from the first ## Open item, Next from the first ## Next item,
#    continuations joined, later items excluded.
root="$tmp/tartib"; mkdir -p "$root/kis/state"
cat > "$root/kis/state/current.md" <<'MD'
# Current

- Branch: main, tracking origin/main at https://example.test/repo.
- Task: slice done. The continuation adds the detail line
  joined into one Task value.
- **Live: v2.6**, this is not a label.

## Open

- **First open item** needs attention, with a second
  indented line that should join.
- Second open item that must not leak.

## Next

1. **First next item** once the prerequisites land.
2. Second next item that must not leak.
MD
out="$("$H" "$root")"
[[ "$out" == *"Blocker: **First open item** needs attention"*"indented line that should join"* ]] || fail "Blocker heading fallback wrong: $out"
[[ "$out" != *"Second open item"* ]] || fail "second Open item leaked"
[[ "$out" == *"Next: **First next item** once the prerequisites land."* ]] || fail "Next heading fallback wrong: $out"
[[ "$out" != *"Second next item"* ]] || fail "second Next item leaked"
[[ "$out" == *"Task: slice done."*"joined into one Task value"* ]] || fail "Task continuation not joined"
(( $(lines "$out") <= budget )) || fail "tartib anchor over budget: $(lines "$out") lines"

# 4. No summary fields at all: a capped head plus a pointer, never the whole file.
root="$tmp/unlabelled"; mkdir -p "$root/kis/state"
{ echo "# Scratch"; echo; i=0; while (( i < 40 )); do echo "prose line $i"; i=$((i + 1)); done; } > "$root/kis/state/current.md"
out="$("$H" "$root")"
[[ "$out" == *"No Branch/Task/Blocker/Next summary fields found"* ]] || fail "fallback message missing"
[[ "$out" == *"read kis/state/current.md"* ]] || fail "fallback pointer missing"
[[ "$out" != *"prose line 39"* ]] || fail "fallback dumped the whole State"
(( $(lines "$out") <= budget )) || fail "fallback anchor over budget: $(lines "$out") lines"

# 5. A very long field is cut at the cap, with an ellipsis.
root="$tmp/long"; mkdir -p "$root/kis/state"
long="$(printf 'x%.0s' $(seq 1 400))"
printf -- '- Branch: main\n- Task: %s\n- Next: go\n' "$long" > "$root/kis/state/current.md"
out="$("$H" "$root")"
task_line="$(printf '%s\n' "$out" | grep '^Task: ')"
[[ "$task_line" == *"..." ]] || fail "long Task not marked cut"
(( ${#task_line} <= 210 )) || fail "long Task not capped: ${#task_line} chars"

# 6. No kis/ and an empty state dir keep the existing messages.
out="$("$H" "$tmp/no-kis")"
[[ "$out" == *"not initialized"* ]] || fail "no-kis message missing"
root="$tmp/emptystate"; mkdir -p "$root/kis/state"
out="$("$H" "$root")"
[[ "$out" == *"No State file found"* ]] || fail "empty-state message missing"

# 7. The budget is a hard cap: a 16-line budget still bounds the output.
out="$(KIS_ANCHOR_MAX_LINES=16 "$H" "$tmp/tartib")"
(( $(lines "$out") <= 16 )) || fail "16-line budget exceeded: $(lines "$out") lines"

# 8. The Antigravity hook injects the same short anchor.
if command -v ruby >/dev/null 2>&1; then
  marker_home="$tmp/markers"; mkdir -p "$marker_home"
  payload="{\"conversationId\":\"conv-session-anchor\",\"workspacePaths\":[\"$tmp/tartib\"]}"
  ag_out="$(printf '%s' "$payload" | TMPDIR="$marker_home" "$A")"
  [[ "$ag_out" == *'"injectSteps"'* ]] || fail "Antigravity hook did not inject"
  [[ "$ag_out" == *'Blocker: **First open item**'* ]] || fail "Antigravity hook did not carry the summary"
  (( ${#ag_out} <= 2500 )) || fail "Antigravity anchor too large: ${#ag_out} chars"
else
  echo "(ruby absent: Antigravity wrapper not exercised)"
fi

echo "session-anchor tests: pass"
