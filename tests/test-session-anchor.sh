#!/usr/bin/env bash
# Guard: the KIS SessionStart anchor prints a short summary (Branch, Run, Task, Blocker, Next) with a
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

# 5b. A long Run keeps its "; live record at <path>" tail whole and shortens the description before it.
root="$tmp/longrun"; mkdir -p "$root/kis/state"
desc="orchestrated release of the fictional gadget covering tasks one through six, including session wiring, plan review guard and state stamp fixes, with a great deal more description text on top"
pointer="; live record at .orch/runs/gadget-1.2/ledger.md"
printf -- '- Branch: main\n- Run: %s%s\n- Task: tune\n' "$desc" "$pointer" > "$root/kis/state/current.md"
out="$("$H" "$root")"
run_line="$(grep '^Run: ' <<< "$out")"
(( ${#desc} + ${#pointer} > 200 )) || fail "test setup: the Run value is not over 200 characters"
[[ "$run_line" == "Run: orchestrated release of the fictional gadget"*"...$pointer" ]] || fail "long Run lost its pointer or its description: $run_line"
(( ${#run_line} - 5 <= 200 )) || fail "long Run not capped: $(( ${#run_line} - 5 )) chars"
# A pointer path longer than the cap stays whole.
longpath="$(printf 'p%.0s' $(seq 1 220))"
printf -- '- Run: short description; live record at .orch/%s/ledger.md\n- Task: tune\n' "$longpath" > "$root/kis/state/current.md"
[[ "$("$H" "$root" | grep '^Run: ')" == "Run: ...; live record at .orch/$longpath/ledger.md" ]] || fail "an over-long pointer path was cut"

# 5b2. Run is the orchestrator pointer only. A `Run:` line that names no live record (an old
#      how-to-run line) is not shown; a pointer before or after it is shown whole.
printf -- '- Run: the fictional gadget needs USB with debugging on\n- Task: tune\n' > "$root/kis/state/current.md"
out="$("$H" "$root")"
[[ "$(grep -c '^Run: ' <<< "$out")" == "0" ]] || fail "a Run line without a live record was shown as a pointer: $out"
[[ "$(grep -c '^Task: tune$' <<< "$out")" == "1" ]] || fail "Task lost beside a non-pointer Run line: $out"
printf -- '- Run: the fictional gadget needs USB\n  with debugging on\n- Task: tune\n- Run: orch run active; live record at .orch/ledger.md\n' > "$root/kis/state/current.md"
[[ "$("$H" "$root" | grep '^Run: ')" == "Run: orch run active; live record at .orch/ledger.md" ]] || fail "a pointer after a non-pointer Run line was not shown"
printf -- '- Run: orch run active; live record at .orch/ledger.md\n- Task: tune\n- Run: the fictional gadget needs USB\n  with debugging on\n' > "$root/kis/state/current.md"
[[ "$("$H" "$root" | grep '^Run: ')" == "Run: orch run active; live record at .orch/ledger.md" ]] || fail "a non-pointer Run line after the pointer changed it"
printf -- '- Run: first run; live record at .orch/one.md\n- Run: second run; live record at .orch/two.md\n  more text\n- Task: tune\n' > "$root/kis/state/current.md"
out="$("$H" "$root")"
[[ "$(grep -c '^Run: ' <<< "$out")" == "1" && "$(grep '^Run: ' <<< "$out")" == "Run: first run; live record at .orch/one.md" ]] || fail "two pointers did not keep the first whole: $out"
printf -- '- Task: tune\r\n- Run: orch run active; live record at .orch/ledger.md\r\n' > "$root/kis/state/current.md"
[[ "$("$H" "$root" | grep '^Run: ')" == "Run: orch run active; live record at .orch/ledger.md" ]] || fail "a CRLF pointer as the last field was not shown whole"
printf -- '- Task: tune\n- Run: orch run active; live record at .orch/ledger.md' > "$root/kis/state/current.md"
[[ "$("$H" "$root" | grep '^Run: ')" == "Run: orch run active; live record at .orch/ledger.md" ]] || fail "a pointer on a last line without a newline was not shown"
printf -- '- Run: orch run active;\n  live record at .orch/ledger.md\n- Task: tune\n' > "$root/kis/state/current.md"
[[ "$("$H" "$root" | grep '^Run: ')" == "Run: orch run active; live record at .orch/ledger.md" ]] || fail "a pointer split over a continuation line was not shown"

# 5c. A State with no summary fields gets a head whose lines are each capped, so the closing pointer
#     line is never pushed past what a host keeps (cmd cuts hook context at 4000 characters).
root="$tmp/longhead"; mkdir -p "$root/kis/state"
{ i=0; while (( i < 12 )); do printf -- '- item %s: ' "$i"; printf 'detail %.0s' $(seq 1 60); echo; i=$((i + 1)); done; } > "$root/kis/state/current.md"
out="$("$H" "$root")"
while IFS= read -r line; do
  (( ${#line} <= 200 )) || fail "a head line is ${#line} characters, over the 200 cap: ${line:0:60}"
done <<< "$out"
(( ${#out} < 3000 )) || fail "summary-less anchor is ${#out} characters, not under 3000"
[[ "$(tail -n 1 <<< "$out")" == "No Branch/Task/Blocker/Next summary fields found; read kis/state/current.md (12 lines) before planning." ]] || fail "closing pointer line missing: $(tail -n 1 <<< "$out")"
[[ "$(grep -c '^- item [0-9]*: detail.*\.\.\.$' <<< "$out")" -ge 1 ]] || fail "a capped head line is not marked with an ellipsis"

# 6. No kis/ and an empty state dir keep the existing messages.
out="$("$H" "$tmp/no-kis")"
[[ "$out" == *"not initialized"* ]] || fail "no-kis message missing"
root="$tmp/emptystate"; mkdir -p "$root/kis/state"
out="$("$H" "$root")"
[[ "$out" == *"No State file found"* ]] || fail "empty-state message missing"

# 7. The budget is a hard cap: an 18-line budget still bounds the output, and a smaller one is
#    raised to 18.
out="$(KIS_ANCHOR_MAX_LINES=18 "$H" "$tmp/tartib")"
(( $(lines "$out") <= 18 )) || fail "18-line budget exceeded: $(lines "$out") lines"
out="$(KIS_ANCHOR_MAX_LINES=16 "$H" "$tmp/tartib")"
(( $(lines "$out") <= 18 )) || fail "16-line budget not raised to 18: $(lines "$out") lines"

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

# 9. A stamped State in a git repo: quiet while it matches, one Stale State line right after the
#    heading block (before the summary) once the code moves on, within the budget either way.
if command -v git >/dev/null 2>&1; then
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.test
  export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.test
  root="$tmp/stamped"; mkdir -p "$root/kis/state"
  git init -q -b main "$root"
  printf 'fictional gadget code\n' > "$root/gadget.txt"
  printf -- '- Branch: main\n- Task: tune the gadget\n- Next: ship\n' > "$root/kis/state/current.md"
  { "$package_dir/scripts/state-stamp.sh" "$root"; cat "$root/kis/state/current.md"; } > "$root/kis/state/new.tmp"
  mv "$root/kis/state/new.tmp" "$root/kis/state/current.md"
  out="$("$H" "$root")"
  grep -q '^Stale State:' <<< "$out" && fail "matching stamp should be quiet: $out"
  printf 'more gadget code\n' >> "$root/gadget.txt"
  out="$("$H" "$root")"
  [[ "$(grep -c '^Stale State: code outside kis/ changed since the last sync (none on main); check State against the repo before trusting Task and Next\.$' <<< "$out")" == "1" ]] || fail "stale line missing or wrong: $out"
  [[ "$(sed -n '9p;10p;11p' <<< "$out" | paste -sd '|' -)" == "## Current State: kis/state/current.md||Stale State: code outside kis/ changed since the last sync (none on main); check State against the repo before trusting Task and Next." ]] || fail "stale line not right after the heading block: $out"
  (( $(lines "$out") <= budget )) || fail "stale anchor over budget: $(lines "$out") lines"
else
  echo "(git absent: stale-State line not exercised)"
fi

# The minimum is 18: a summary-less State under a tiny budget fills exactly the raised budget.
out="$(KIS_ANCHOR_MAX_LINES=10 "$H" "$tmp/unlabelled")"
(( $(lines "$out") == 18 )) || fail "budget below the minimum not raised to 18: $(lines "$out") lines"

# 10. A Run pointer line is a summary field between Branch and Task. Without one the output is
#     exactly what it was (no Run line, nothing else added).
root="$tmp/run"; mkdir -p "$root/kis/state"
cat > "$root/kis/state/current.md" <<'MD'
# Current

- Task: finish the gadget
- Next: merge task 2
- Blocker: none
- Run: orch run active; live record at .orch/ledger.md
- Branch: main
MD
out="$("$H" "$root")"
[[ "$(grep -c '^Run: orch run active; live record at \.orch/ledger\.md$' <<< "$out")" == "1" ]] || fail "Run line missing or wrong: $out"
[[ "$(grep -E '^(Branch|Run|Task|Blocker|Next): ' <<< "$out" | cut -d: -f1 | paste -sd ',' -)" == "Branch,Run,Task,Blocker,Next" ]] || fail "field order wrong: $out"
(( $(lines "$out") <= budget )) || fail "Run anchor over budget: $(lines "$out") lines"
printf -- '- Branch: main\n- Task: finish the gadget\n- Blocker: none\n- Next: merge task 2\n' > "$root/kis/state/current.md"
out="$("$H" "$root")"
[[ "$out" != *"Run:"* ]] || fail "invented a Run line: $out"
[[ "$(sed -n '11,14p' <<< "$out" | paste -sd '|' -)" == "Branch: main|Task: finish the gadget|Blocker: none|Next: merge task 2" ]] || fail "State without Run changed: $out"
(( $(lines "$out") == 16 )) || fail "State without Run: expected 16 lines, got $(lines "$out")"

# 11. All five fields plus a Stale State line, at the minimum budget, still fit.
if command -v git >/dev/null 2>&1; then
  root="$tmp/runstale"; mkdir -p "$root/kis/state"
  git init -q -b main "$root"
  printf 'fictional gadget code\n' > "$root/gadget.txt"
  printf -- '- Branch: main\n- Run: orch run active; live record at .orch/ledger.md\n- Task: tune the gadget\n- Blocker: none\n- Next: ship\n' > "$root/kis/state/current.md"
  { "$package_dir/scripts/state-stamp.sh" "$root"; cat "$root/kis/state/current.md"; } > "$root/kis/state/new.tmp"
  mv "$root/kis/state/new.tmp" "$root/kis/state/current.md"
  printf 'more gadget code\n' >> "$root/gadget.txt"
  out="$(KIS_ANCHOR_MAX_LINES=18 "$H" "$root")"
  grep -q '^Stale State:' <<< "$out" || fail "stale line missing: $out"
  [[ "$(grep -E '^(Branch|Run|Task|Blocker|Next): ' <<< "$out" | cut -d: -f1 | paste -sd ',' -)" == "Branch,Run,Task,Blocker,Next" ]] || fail "five fields missing under Stale State: $out"
  (( $(lines "$out") == 18 )) || fail "five fields plus Stale State: expected 18 lines, got $(lines "$out")"
  grep -q '^Full State: kis/state/current.md' <<< "$out" || fail "pointer cut by the budget: $out"
fi

# 12. Locale: an invalid byte keeps the summary, and a cut never splits a multibyte character,
#     under a UTF-8 locale and with no locale at all.
root="$tmp/locale"; mkdir -p "$root/kis/state"
printf -- '- Branch: main\n- Task: bad \377\376 byte\n- Next: go\n' > "$root/kis/state/current.md"
for env_args in "LC_ALL=C.UTF-8" "-u LANG -u LC_ALL -u LC_CTYPE"; do
  out="$(env $env_args "$H" "$root")"
  [[ "$(grep -c '^Task: bad ' <<< "$out")" == 1 ]] || fail "invalid byte lost the Task under [$env_args]: $out"
done
# 'é' is two bytes; 99 ASCII bytes put the 200-byte cut (197 kept) inside the 99th é.
printf -- '- Branch: main\n- Task: %s\n- Next: go\n' "$(printf 'a%.0s' $(seq 1 100))$(printf 'é%.0s' $(seq 1 100))" > "$root/kis/state/current.md"
for env_args in "LC_ALL=C.UTF-8" "-u LANG -u LC_ALL -u LC_CTYPE"; do
  out="$(env $env_args "$H" "$root")"
  task="$(grep '^Task: ' <<< "$out")" || fail "long multibyte Task missing under [$env_args]"
  [[ "$task" == *'...' ]] || fail "long Task not cut under [$env_args]: $task"
  printf '%s' "$task" | LC_ALL=C.UTF-8 iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || fail "cut split a multibyte character under [$env_args]"
done

# The docs reserve Run: for the pointer the anchor shows, and name the how-to-run line.
grep -qF '`Run:` is reserved for this pointer; the how-to-run line is `How to run:`.' "$package_dir/SKILL.md" || fail "SKILL.md does not reserve Run:"
grep -qxF -- '- `Run:` is reserved for this pointer. State'"'"'s line on how to run the project is `How to run:`, and a `Run:` line that names no live record is not a pointer.' "$package_dir/references/execution.md" || fail "execution.md (Orchestrated Runs) does not own the Run: reservation"
grep -qxF '## Orchestrated Runs' "$package_dir/references/execution.md" || fail "execution.md lost its Orchestrated Runs section"
grep -qF 'Read [execution.md](references/execution.md) (Orchestrated Runs) before changing State.' "$package_dir/SKILL.md" || fail "SKILL.md does not point at Orchestrated Runs"
grep -qF -- '- how to run it, as a `How to run:` line' "$package_dir/references/file-hygiene.md" || fail "file-hygiene.md does not name the How to run: line"
grep -qF 'and so is a `Run:` line that names no live record' "$package_dir/commands/check.md" || fail "check.md does not flag a Run: line without a live record"

echo "session-anchor tests: pass"
