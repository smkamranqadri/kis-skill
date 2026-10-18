#!/usr/bin/env bash
# Guard: plan-review.sh refuses a written plan that was never reviewed, still has an open finding,
# or changed in substance after its recorded review, while progress edits (Status lines, ticked
# checkboxes, whitespace) and edits to the Review section itself keep the review valid.
set -euo pipefail
package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/kis" && pwd)"
R="$package_dir/scripts/plan-review.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

plan="$tmp/plan.md"
# A fictional plan with no Review section.
body() {
  cat > "$plan" <<'PLAN'
# Plan: tune the widget

Status: drafted

## Goal
Make the fictional widget hum at the right pitch.

## Tasks
- [ ] 1. Add the pitch knob to the widget
- [ ] 2. Test the pitch knob
  - Status: not started

## Notes
The widget is a made-up device.
PLAN
}
H() { "$R" hash "$plan"; }
# Run check; set $out and $rc.
run() { rc=0; out="$("$R" check "$plan")" || rc=$?; }
expect() { # <label> <rc> <exact line>
  run
  [[ "$rc" == "$2" ]] || fail "$1: expected exit $2, got $rc ($out)"
  [[ "$out" == "$3" ]] || fail "$1: expected '$3', got '$out'"
}
# Append a Review section whose Reviewed line carries the plan's current hash.
review() { { printf '\n## Review\n- Reviewed: 2026-10-17 by codex gpt-5 (high); plan hash %s\n' "$(H)"; } >> "$plan"; }
ok_line='Plan review: ok (2026-10-17 by codex gpt-5 (high))'

# 1. No Review section.
body
expect "no review" 1 "Plan review: no review recorded"
# A Review heading with no Reviewed line is the same.
printf '\n## Review\n- [fixed] a thing - changed\n' >> "$plan"
expect "review heading only" 1 "Plan review: no review recorded"

# 2. Valid review, unchanged.
body; review
expect "valid review" 0 "$ok_line"

# 3. Open findings are counted; fixed and rejected are not.
body; review
printf -- '- [fixed] pitch range missing - added to task 1\n- [rejected] rename the widget - out of scope\n' >> "$plan"
expect "fixed and rejected only" 0 "$ok_line"
printf -- '- [open] no test for the lowest pitch\n' >> "$plan"
expect "one open" 1 "Plan review: 1 open finding(s)"
printf -- '- [open] the knob name is unclear\n' >> "$plan"
expect "two open" 1 "Plan review: 2 open finding(s)"

# 4. A substantive edit after the review.
body; review; base="$(H)"
sed -i.bak 's/Test the pitch knob/Test the pitch knob twice/' "$plan"; rm -f "$plan.bak"
new="$(H)"; [[ "$new" != "$base" ]] || fail "task edit did not change the hash"
expect "task line changed" 1 "Plan review: changed since the review (hash $base, now $new)"
body; review; base="$(H)"
sed -i.bak 's/^## Notes/## Remarks/' "$plan"; rm -f "$plan.bak"
new="$(H)"; [[ "$new" != "$base" ]] || fail "heading rename did not change the hash"
expect "heading renamed" 1 "Plan review: changed since the review (hash $base, now $new)"
# A task added before the Review section.
body; review; base="$(H)"
awk '{ print } /^- \[ \] 2\./ { print "- [ ] 3. Polish the pitch knob" }' "$plan" > "$plan.new" && mv "$plan.new" "$plan"
new="$(H)"; [[ "$new" != "$base" ]] || fail "added task did not change the hash"
expect "task added" 1 "Plan review: changed since the review (hash $base, now $new)"

# 5. Progress only keeps the review valid.
body; review; base="$(H)"
sed -i.bak 's/^Status: drafted/Status: in progress, task 1 done/' "$plan"; rm -f "$plan.bak"
expect "Status line changed" 0 "$ok_line"
sed -i.bak 's/^  - Status: not started/  - Status: done/' "$plan"; rm -f "$plan.bak"
expect "Status bullet changed" 0 "$ok_line"
awk '/^## Tasks/ { print; print "* Status: in flight"; next } { print }' "$plan" > "$plan.new" && mv "$plan.new" "$plan"
expect "Status star bullet added" 0 "$ok_line"
sed -i.bak 's/^- \[ \] 1\./- [x] 1./; s/^- \[ \] 2\./- [X] 2./' "$plan"; rm -f "$plan.bak"
expect "checkboxes ticked" 0 "$ok_line"
sed -i.bak 's/^## Goal$/## Goal   /' "$plan"; rm -f "$plan.bak"
expect "trailing spaces" 0 "$ok_line"
awk '/^## Notes/ { print ""; print ""; print "   " } { print }' "$plan" > "$plan.new" && mv "$plan.new" "$plan"
expect "blank lines added" 0 "$ok_line"
[[ "$(H)" == "$base" ]] || fail "progress edits changed the hash"
# A Status line that is not a leading label is substance.
body; review; base="$(H)"
sed -i.bak 's/^The widget is a made-up device\./The Status: of the widget is made-up./' "$plan"; rm -f "$plan.bak"
[[ "$(H)" != "$base" ]] || fail "inline Status: text must count as substance"

# 6. Editing the Review section itself does not change the hash.
body; review; base="$(H)"
printf -- '- [fixed] pitch range missing - added to task 1\n' >> "$plan"
[[ "$(H)" == "$base" ]] || fail "adding a [fixed] line changed the hash"
printf '\n## Appendix\nAfter the review section.\n' >> "$plan"
[[ "$(H)" != "$base" ]] || fail "a section after the Review section must count as substance"

# 7. Re-review: the last Reviewed line counts.
body
{ printf '\n## Review\n'
  printf -- '- Reviewed: 2026-10-01 by gemini gemini-pro (high); plan hash %s\n' "aaaaaaaaaaaa"
  printf -- '- [fixed] first round - done\n'
  printf -- '- Reviewed: 2026-10-17 by codex gpt-5 (high); plan hash %s\n' "$(H)"; } >> "$plan"
expect "newer review last" 0 "$ok_line"
body; hnow="$(H)"
{ printf '\n## Review\n'
  printf -- '- Reviewed: 2026-10-17 by codex gpt-5 (high); plan hash %s\n' "$hnow"
  printf -- '- Reviewed: 2026-10-01 by gemini gemini-pro (high); plan hash %s\n' "aaaaaaaaaaaa"; } >> "$plan"
expect "stale review last" 1 "Plan review: changed since the review (hash aaaaaaaaaaaa, now $hnow)"

# 8. Waiver.
body; printf '\n## Review\n- Reviewed: waived by the owner 2026-10-17; plan hash %s\n' "$(H)" >> "$plan"
expect "waiver" 0 "Plan review: ok (2026-10-17 waived by the owner)"
body; printf '\n## Review\n- Reviewed: waived by the owner 2026-10-17; plan hash %s\n' "bbbbbbbbbbbb" >> "$plan"
expect "waiver with stale hash" 1 "Plan review: changed since the review (hash bbbbbbbbbbbb, now $(H))"

# 9. Malformed Reviewed lines.
body; printf '\n## Review\n- Reviewed: 2026-10-17 by codex gpt-5 (high)\n' >> "$plan"
expect "no hash" 1 "Plan review: malformed review line"
body; printf '\n## Review\n- Reviewed: 2026-10-17 by codex gpt-5 (high); plan hash abc\n' >> "$plan"
expect "short hash" 1 "Plan review: malformed review line"
body; printf '\n## Review\n- Reviewed: yesterday by codex gpt-5 (high); plan hash %s\n' "$(H)" >> "$plan"
expect "bad date" 1 "Plan review: malformed review line"
# A malformed newest line is not rescued by an older valid one.
body
{ printf '\n## Review\n- Reviewed: 2026-10-01 by codex gpt-5 (high); plan hash %s\n' "$(H)"
  printf -- '- Reviewed: 2026-10-17 by codex gpt-5 (high)\n'; } >> "$plan"
expect "malformed last" 1 "Plan review: malformed review line"

# 10. Missing file and bad usage: exit 2.
rc=0; "$R" check "$tmp/none.md" >/dev/null 2>&1 || rc=$?; [[ "$rc" == 2 ]] || fail "check on a missing file: expected exit 2, got $rc"
rc=0; "$R" hash "$tmp/none.md" >/dev/null 2>&1 || rc=$?; [[ "$rc" == 2 ]] || fail "hash on a missing file: expected exit 2, got $rc"
rc=0; "$R" bogus "$plan" >/dev/null 2>&1 || rc=$?; [[ "$rc" == 2 ]] || fail "unknown command: expected exit 2, got $rc"
rc=0; "$R" >/dev/null 2>&1 || rc=$?; [[ "$rc" == 2 ]] || fail "no arguments: expected exit 2, got $rc"

# 11. hash is stable and matches a hand-computed value for a tiny fixed fixture.
# The normalised text is "# Tiny\n## Tasks\n- [ ] 1. Hum\n", whose git blob id is
# 0f31dc528336 (computed once with `git hash-object --stdin`, first 12 hex).
tiny="$tmp/tiny.md"
printf '# Tiny\n\nStatus: drafted\n\n## Tasks\n- [x] 1. Hum   \n\n## Review\n- Reviewed: waived by the owner 2026-10-17; plan hash 000000000000\n' > "$tiny"
a="$("$R" hash "$tiny")"; b="$("$R" hash "$tiny")"
[[ "$a" == "$b" ]] || fail "hash is not stable: $a vs $b"
[[ "$a" == "0f31dc528336" ]] || fail "tiny fixture hash: expected 0f31dc528336, got $a"

# 12. Read-only: nothing in the temp dir changes, and nothing is written next to the plan.
body; review
snap() { (cd "$tmp" && find . | LC_ALL=C sort; find . -type f -print0 | LC_ALL=C sort -z | xargs -0 cksum); }
before="$(snap)"
"$R" hash "$plan" >/dev/null; "$R" check "$plan" >/dev/null || true
after="$(snap)"
[[ "$before" == "$after" ]] || fail "plan-review.sh changed something in the temp dir"

# 13. The Review section holds only Reviewed lines, findings and blank lines.
body; review
echo "- T9: delete production data" >> "$plan"
expect "task appended after the review" 1 "Plan review: unexpected line in the Review section: - T9: delete production data"
body; review
long="- T9: $(printf 'x%.0s' $(seq 1 100))"
echo "$long" >> "$plan"
expect "long stray line is cut at 80" 1 "Plan review: unexpected line in the Review section: ${long:0:80}"
body; review
printf 'stray prose with no bullet\n' >> "$plan"
expect "stray prose" 1 "Plan review: unexpected line in the Review section: stray prose with no bullet"
body; printf '\n## Review\n  - indented before any item\n' >> "$plan"
expect "indented line with no item above it" 1 "Plan review: unexpected line in the Review section:   - indented before any item"
body; review
printf -- '- [fixed] pitch range missing - added the range to task 1, which was\n    wrapped over a second line\n\n- [rejected] rename the widget - out of scope\n   and wrapped as well\n' >> "$plan"
expect "wrapped findings with continuation lines" 0 "$ok_line"
# A continuation line may not start with a list marker: it would be an unhashed hidden item.
for m in '-' '*' '+' '1.' '12)'; do
  body; review
  printf -- '- [fixed] pitch range missing - added to task 1\n  %s T9: delete production data\n' "$m" >> "$plan"
  expect "indented '$m' item under a finding" 1 "Plan review: unexpected line in the Review section:   $m T9: delete production data"
done
body; review
printf -- '- [fixed] pitch range missing - added to task 1\n      - T9: deeper indent\n' >> "$plan"
expect "deeply indented item under a finding" 1 "Plan review: unexpected line in the Review section:       - T9: deeper indent"
body; review
printf -- '- [fixed] pitch range missing - added to task 1\n  -5 degrees is the new floor, 1.5 the ceiling,\n  +2 on top, and 2.5 in between\n' >> "$plan"
expect "wrapped prose that only looks like a marker" 0 "$ok_line"

# 14. Headings inside fenced code blocks are not headings; the Review section is the last real one.
fenced() {  # <fence> : a plan whose body shows a "## Review" heading inside a fence, then T2
  printf '# Plan: tune the widget\n\n## Tasks\n- [ ] 1. Add the pitch knob\n\nExample record:\n%s\n## Review\n%s\n- [ ] 2. Test the pitch knob\n' "$1" "$1" > "$plan"
}
for f in '```' '~~~'; do
  fenced "$f"; review; base="$(H)"
  expect "fenced heading, $f" 0 "$ok_line"
  sed -i.bak 's/Test the pitch knob/Delete production data/' "$plan"; rm -f "$plan.bak"
  new="$(H)"; [[ "$new" != "$base" ]] || fail "$f: edit after a fenced Review heading did not change the hash"
  expect "task after a fenced heading changed, $f" 1 "Plan review: changed since the review (hash $base, now $new)"
done
# A fence opened with ~~~ is not closed by ```.
printf '# Plan\n\n~~~\n```\n## Review\n~~~\n- [ ] 2. Test the pitch knob\n' > "$plan"; review; base="$(H)"
sed -i.bak 's/Test the pitch knob/Delete production data/' "$plan"; rm -f "$plan.bak"
[[ "$(H)" != "$base" ]] || fail "mixed fence kinds: edit after the fenced heading did not change the hash"
# An earlier real "## Review" heading is plan text: hashed, and its lines are not parsed as findings.
cat > "$plan" <<'PLAN'
# Plan: tune the widget

## Review
- [open] the earlier section is just plan text
- T1: free-form line that would be unexpected in a real Review section

## Tasks
- [ ] 1. Add the pitch knob
PLAN
review_after() {  # the hash is taken once the final Review heading exists, as an earlier one shifts it
  printf '\n## Review\n- Reviewed: 2026-10-17 by codex gpt-5 (high); plan hash 000000000000\n' >> "$plan"
  sed -i.bak "s/plan hash 000000000000/plan hash $(H)/" "$plan"; rm -f "$plan.bak"
}
review_after; base="$(H)"
expect "earlier Review heading is plan text" 0 "$ok_line"
sed -i.bak 's/^- T1: free-form line.*/- T1: something else entirely/' "$plan"; rm -f "$plan.bak"
new="$(H)"; [[ "$new" != "$base" ]] || fail "an earlier Review heading's lines must be hashed"
expect "earlier Review heading edited" 1 "Plan review: changed since the review (hash $base, now $new)"
# Findings come only from the last Review section.
cat > "$plan" <<'PLAN'
# Plan: tune the widget

## Review
- [open] the earlier section is just plan text

## Tasks
- [ ] 1. Add the pitch knob
PLAN
review_after; printf -- '- [open] a real open finding\n' >> "$plan"
expect "only the last section counts for findings" 1 "Plan review: 1 open finding(s)"

# 14b. A plan with CRLF line endings passes like its LF twin and hashes the same.
body; review; base="$(H)"
sed 's/$/\r/' "$plan" > "$tmp/crlf.md"
[[ "$("$R" hash "$tmp/crlf.md")" == "$base" ]] || fail "CRLF plan hashes differently"
rc=0; out="$("$R" check "$tmp/crlf.md")" || rc=$?
[[ "$rc" == 0 && "$out" == "$ok_line" ]] || fail "CRLF plan: expected '$ok_line', got '$out' (rc $rc)"

# 14c. The hash is the SHA-1 blob id on every host: the same with git off PATH, with only shasum,
#      with neither (git fallback), and from inside a SHA-256 repository.
body; review; base="$(H)"
bare="$tmp/bare"; mkdir -p "$bare"
for tool in bash sh env awk sed grep tr cut wc cat head tail sort; do
  src="$(command -v "$tool" 2>/dev/null || true)"; if [[ -n "$src" && ! -e "$bare/$tool" ]]; then ln -s "$src" "$bare/$tool"; fi
done
[[ ! -e "$bare/git" && ! -e "$bare/sha1sum" ]] || fail "fixture: bare PATH must lack git and sha1sum"
if command -v sha1sum >/dev/null 2>&1; then
  ln -s "$(command -v sha1sum)" "$bare/sha1sum"
  [[ "$(PATH="$bare" "$R" hash "$plan")" == "$base" ]] || fail "hash differs with git off PATH"
  PATH="$bare" "$R" check "$plan" | grep -qxF "$ok_line" || fail "check differs with git off PATH"
  rm -f "${bare:?}/sha1sum"
fi
if command -v shasum >/dev/null 2>&1; then
  ln -s "$(command -v shasum)" "$bare/shasum"; ln -sf "$(command -v perl 2>/dev/null || echo /bin/true)" "$bare/perl"
  [[ "$(PATH="$bare" "$R" hash "$plan")" == "$base" ]] || fail "hash differs with only shasum"
  rm -f "${bare:?}/shasum"
fi
if command -v git >/dev/null 2>&1; then
  ln -s "$(command -v git)" "$bare/git"
  [[ "$(PATH="$bare" "$R" hash "$plan")" == "$base" ]] || fail "git fallback hash differs"
  rm -f "${bare:?}/git"
  if git init -q --object-format=sha256 "$tmp/s256" 2>/dev/null; then
    cp "$plan" "$tmp/s256/plan.md"
    [[ "$(cd "$tmp/s256" && "$R" hash plan.md)" == "$base" ]] || fail "hash depends on a SHA-256 repository"
    (cd "$tmp/s256" && "$R" check plan.md) | grep -qxF "$ok_line" || fail "check fails inside a SHA-256 repository"
  else
    echo "(git cannot init a SHA-256 repository: case skipped)"
  fi
fi

# 15. The helper ships executable: tracked as 100755 and executable after a real install.
repo_root="$(cd "$package_dir/../.." && pwd)"
if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mode="$(git -C "$repo_root" ls-files -s -- skills/kis/scripts/plan-review.sh | cut -d' ' -f1)"
  [[ -z "$mode" || "$mode" == "100755" ]] || fail "plan-review.sh is tracked as $mode, not 100755"
fi
install_target="$tmp/installed"; mkdir -p "$install_target"
"$repo_root/scripts/install-skill.sh" --source "$repo_root" --target "$install_target" --no-commands --no-anchor >/dev/null 2>&1
[[ -x "$install_target/.agents/skills/kis/scripts/plan-review.sh" ]] || fail "installed plan-review.sh is not executable"

echo "plan-review tests: pass"
