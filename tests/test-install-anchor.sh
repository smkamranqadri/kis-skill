#!/usr/bin/env bash
set -euo pipefail

script_under_test="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/kis/scripts" && pwd)/install-anchor.sh}"
package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/kis" && pwd)"
hook_script="$package_dir/hooks/session-anchor.sh"
antigravity_hook_script="$package_dir/hooks/antigravity-anchor.sh"
cmd_hook_script="$package_dir/hooks/cmd-anchor.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
# Nothing here may touch the real home: the hosts keep user-level files there.
export HOME="$tmp_dir/home"; mkdir -p "$HOME"

target_root="$tmp_dir/project"
settings="$target_root/.claude/settings.json"
hooks_json="$target_root/.agents/hooks.json"
agents_file="$target_root/AGENTS.md"

mkdir -p "$target_root/.claude"
cat > "$settings" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(git status:*)"]
  },
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [{ "type": "command", "command": "echo existing" }]
      }
    ]
  }
}
EOF
mkdir -p "$target_root/.agents"
cat > "$hooks_json" <<'EOF'
{
  "existing-guard": {
    "PreToolUse": [
      {
        "matcher": "run_command",
        "hooks": [{ "type": "command", "command": "echo guard" }]
      }
    ]
  }
}
EOF
printf '# Project\n\nExisting instructions.\n' > "$agents_file"
# Codex and Command Code files that already carry other tools' hooks and unrelated keys.
codex_hooks="$target_root/.codex/hooks.json"
cmd_settings="$target_root/.commandcode/settings.json"
mkdir -p "$target_root/.codex" "$target_root/.commandcode"
cat > "$codex_hooks" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "bash other-tool-start.sh", "timeout": 10 }] }
    ],
    "SessionEnd": [
      { "hooks": [{ "type": "command", "command": "bash other-tool-end.sh", "timeout": 10 }] }
    ]
  }
}
EOF
cat > "$cmd_settings" <<'EOF'
{
  "permissions": { "allow": ["Bash(git status:*)"] },
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "bash other-tool-start.sh", "timeout": 10 }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "bash other-tool-stop.sh", "timeout": 10 }] }
    ]
  }
}
EOF
cp "$codex_hooks" "$tmp_dir/codex-original.json"
cp "$cmd_settings" "$tmp_dir/cmd-original.json"

fail() {
  echo "$*" >&2
  exit 1
}

count_kis_hooks() {
  ruby -rjson -e '
    data = JSON.parse(File.read(ARGV.fetch(0)))
    entries = data.dig("hooks", "SessionStart") || []
    puts entries.sum { |e| Array(e["hooks"]).count { |h| h["command"].to_s.include?("session-anchor.sh") } }
  ' "$settings"
}

# Number of SessionStart hook commands in a Codex/cmd file that contain a marker.
count_marker() {  # <file> <marker>
  ruby -rjson -e '
    entries = JSON.parse(File.read(ARGV[0])).dig("hooks", "SessionStart") || []
    puts entries.sum { |e| Array(e["hooks"]).count { |h| h["command"].to_s.include?(ARGV[1]) } }
  ' "$1" "$2"
}
# Same JSON value, ignoring formatting.
same_json() { ruby -rjson -e 'exit(JSON.parse(File.read(ARGV[0])) == JSON.parse(File.read(ARGV[1])) ? 0 : 1)' "$1" "$2"; }

read_cmd() {  # <settings file> <marker>
  ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).dig("hooks","SessionStart").flat_map { |e| e["hooks"] }.map { |h| h["command"] }.grep(Regexp.new(ARGV[1])).first' "$1" "$2"
}
set_hook() {  # <settings file> <marker> <command> <timeout or none>: rewrite the KIS entry in place
  ruby -rjson -e 'path, m, c, t = ARGV; d = JSON.parse(File.read(path))
    d["hooks"]["SessionStart"].each { |e| e["hooks"].each { |h| next unless h["command"].include?(m); h["command"] = c; t == "none" ? h.delete("timeout") : h["timeout"] = t.to_i } }
    File.write(path, JSON.pretty_generate(d) + "\n")' "$@"
}
read_timeout() {  # <settings file> <marker>
  ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).dig("hooks","SessionStart").flat_map { |e| e["hooks"] }.select { |h| h["command"].include?(ARGV[1]) }.first["timeout"].inspect' "$1" "$2"
}

first_output="$("$script_under_test" --target "$target_root")"

[[ "$(count_kis_hooks)" == "1" ]] || fail "anchor hook was not registered exactly once"
[[ "$(count_marker "$codex_hooks" kis/hooks/session-anchor.sh)" == "1" ]] || fail "Codex hook was not registered exactly once"
[[ "$(count_marker "$cmd_settings" kis/hooks/cmd-anchor.sh)" == "1" ]] || fail "Command Code hook was not registered exactly once"
[[ "$(count_marker "$codex_hooks" other-tool-start.sh)" == "1" ]] || fail "Codex install lost another tool's SessionStart hook"
[[ "$(count_marker "$cmd_settings" other-tool-start.sh)" == "1" ]] || fail "Command Code install lost another tool's SessionStart hook"
grep -q 'other-tool-end.sh' "$codex_hooks" || fail "Codex install lost another tool's SessionEnd hook"
grep -q 'other-tool-stop.sh' "$cmd_settings" || fail "Command Code install lost another tool's Stop hook"
grep -q '"Bash(git status:\*)"' "$cmd_settings" || fail "Command Code install lost unrelated settings"
[[ "$(grep -c '^Codex: run /hooks once and trust the KIS SessionStart hook\.' <<< "$first_output")" == "1" ]] || fail "first install did not print the Codex trust step exactly once: $first_output"
[[ "$(grep -c 'Command Code SessionStart hook: added to' <<< "$first_output")" == "1" ]] || fail "first install did not report the Command Code hook"
cmp -s "$codex_hooks.kis-bak" "$tmp_dir/codex-original.json" || fail "no byte-identical backup of the Codex file"
cmp -s "$cmd_settings.kis-bak" "$tmp_dir/cmd-original.json" || fail "no byte-identical backup of the Command Code file"
grep -q '"kis-anchor"' "$hooks_json" || fail "Antigravity hook was not registered"
grep -q '"Bash(git status:\*)"' "$settings" || fail "existing settings content was lost"
grep -q 'echo existing' "$settings" || fail "existing hook was lost"
grep -q 'Existing instructions.' "$agents_file" || fail "existing instructions were lost"
grep -q '<!-- kis:anchor:start -->' "$agents_file" || fail "KIS block was not added"
grep -q '/kis:start' "$agents_file" || fail "KIS block is missing the command list"
grep -q '"kis-anchor"' "$hooks_json" || fail "Antigravity hook was not registered"
grep -q './skills/kis/hooks/antigravity-anchor.sh' "$hooks_json" || fail "Antigravity hook command is not relative to .agents/"
grep -q '"PreInvocation"' "$hooks_json" || fail "Antigravity hook is not on PreInvocation"
grep -q 'echo guard' "$hooks_json" || fail "an unrelated Antigravity hook was lost"

# A fresh entry carries the 20 s hook timeout, and the installed commands end their walk-up when the
# session directory is unknown (PWD empty after a getcwd failure) or relative. These run right after
# the first install so that a regression is caught here, not by a later "already installed" check.
for host in "Codex|$codex_hooks|session-anchor" "Command Code|$cmd_settings|cmd-anchor"; do
  IFS='|' read -r hname hfile hmarker <<< "$host"
  [[ "$(read_timeout "$hfile" "$hmarker")" == "20" ]] || fail "a fresh $hname entry does not carry the 20 s timeout"
done
if command -v timeout >/dev/null 2>&1; then
  gone="$tmp_dir/gone"; mkdir -p "$gone"
  for c in "$(read_cmd "$codex_hooks" session-anchor)" "$(read_cmd "$cmd_settings" cmd-anchor)"; do
    rc=0; (cd "$gone" && rmdir "$gone" && env -u PWD timeout 3 sh -c "$c" < /dev/null >/dev/null 2>&1) || rc=$?
    [[ "$rc" == 0 ]] || fail "a hook command spun (exit $rc) when the session directory is gone"
    mkdir -p "$gone"
    rc=0; (cd "$target_root" && env PWD=relative/dir timeout 3 sh -c "$c" < /dev/null >/dev/null 2>&1) || rc=$?
    [[ "$rc" == 0 ]] || fail "a hook command spun (exit $rc) on a relative PWD"
  done
else
  echo "(timeout absent: the empty-PWD walk-up case was not run)"
fi

second_run="$("$script_under_test" --target "$target_root")"
[[ "$(count_kis_hooks)" == "1" ]] || fail "re-running duplicated the anchor hook"
[[ "$(count_marker "$codex_hooks" kis/hooks/session-anchor.sh)" == "1" ]] || fail "re-running duplicated the Codex hook"
[[ "$(count_marker "$cmd_settings" kis/hooks/cmd-anchor.sh)" == "1" ]] || fail "re-running duplicated the Command Code hook"
[[ "$(grep -c '^Codex SessionStart hook: already installed$' <<< "$second_run")" == "1" ]] || fail "re-run did not report the Codex hook as already installed: $second_run"
[[ "$second_run" != *"trust the KIS SessionStart hook"* ]] || fail "re-run repeated the Codex trust step"
[[ "$(grep -c '<!-- kis:anchor:start -->' "$agents_file")" == "1" ]] || fail "re-running duplicated the KIS block"

check_output="$("$script_under_test" --target "$target_root" --check)"
[[ "$check_output" == *"installed"* ]] || fail "--check did not report the hook"
[[ "$check_output" == *"Antigravity PreInvocation hook: installed"* ]] || fail "--check did not report the Antigravity hook"
[[ "$(grep -c '^Codex SessionStart hook: installed$' <<< "$check_output")" == "1" ]] || fail "--check did not report the Codex hook"
[[ "$(grep -c '^Command Code SessionStart hook: installed$' <<< "$check_output")" == "1" ]] || fail "--check did not report the Command Code hook"
[[ "$check_output" == *"KIS block present"* ]] || fail "--check did not report the block"

"$script_under_test" --target "$target_root" --remove >/dev/null
[[ "$(count_kis_hooks)" == "0" ]] || fail "--remove left the anchor hook"
grep -q 'kis-anchor' "$hooks_json" && fail "--remove left the Antigravity hook"
grep -q 'echo guard' "$hooks_json" || fail "--remove deleted an unrelated Antigravity hook"
grep -q 'echo existing' "$settings" || fail "--remove deleted an unrelated hook"
same_json "$codex_hooks" "$tmp_dir/codex-original.json" || fail "--remove did not restore the Codex file to its other hooks only"
same_json "$cmd_settings" "$tmp_dir/cmd-original.json" || fail "--remove did not restore the Command Code file to its other settings only"
check_removed="$("$script_under_test" --target "$target_root" --check)"
[[ "$(grep -c '^Codex SessionStart hook: missing$' <<< "$check_removed")" == "1" ]] || fail "--check after --remove still reports the Codex hook"
[[ "$(grep -c '^Command Code SessionStart hook: missing$' <<< "$check_removed")" == "1" ]] || fail "--check after --remove still reports the Command Code hook"
grep -q '<!-- kis:anchor:start -->' "$agents_file" && fail "--remove left the KIS block"
grep -q 'Existing instructions.' "$agents_file" || fail "--remove deleted unrelated instructions"
[[ "$(cat "$agents_file"; printf x)" == "$(printf '# Project\n\nExisting instructions.\nx')" ]] || fail "--remove did not hand AGENTS.md back byte for byte: $(od -c "$agents_file" | tail -n 3)"

settings_root="$tmp_dir/settings-existing"; mkdir -p "$settings_root/.claude"
printf '{}\n' > "$settings_root/.claude/settings.json"; cp "$settings_root/.claude/settings.json" "$tmp_dir/claude-empty-original.json"
fresh_root="$tmp_dir/fresh"
"$script_under_test" --target "$fresh_root" >/dev/null
[[ -f "$fresh_root/.codex/hooks.json" ]] || fail "Codex hooks file was not created"
[[ -f "$fresh_root/.commandcode/settings.json" ]] || fail "Command Code settings file was not created"
[[ ! -e "$fresh_root/.codex/hooks.json.kis-bak" && ! -e "$fresh_root/.commandcode/settings.json.kis-bak" ]] || fail "a backup was written for a file that did not exist"
"$script_under_test" --target "$fresh_root" --remove >/dev/null
[[ ! -e "$fresh_root/.codex/hooks.json" && ! -e "$fresh_root/.commandcode/settings.json" ]] || fail "--remove left empty Codex or Command Code files"
[[ ! -e "$fresh_root/.claude/settings.json" && ! -e "$fresh_root/.claude/settings.json.kis-bak" ]] || fail "--remove left an empty Claude settings file or a backup on a fresh project: $(cat "$fresh_root/.claude/settings.json" 2>/dev/null)"
# A Claude settings file the user already had survives --remove with its own content.
"$script_under_test" --target "$settings_root" --no-instructions >/dev/null
"$script_under_test" --target "$settings_root" --remove --no-instructions >/dev/null
same_json "$settings_root/.claude/settings.json" "$tmp_dir/claude-empty-original.json" || fail "--remove changed a pre-existing Claude settings file: $(cat "$settings_root/.claude/settings.json")"
"$script_under_test" --target "$fresh_root" >/dev/null
nohook_root="$tmp_dir/nohook"
"$script_under_test" --target "$nohook_root" --no-hook --no-instructions >/dev/null
[[ ! -e "$nohook_root/.codex" && ! -e "$nohook_root/.commandcode" && ! -e "$nohook_root/.claude" ]] || fail "--no-hook still wrote a hook file"
[[ -f "$fresh_root/.claude/settings.json" ]] || fail "settings file was not created"
[[ -f "$fresh_root/AGENTS.md" ]] || fail "AGENTS.md was not created"

kis_root="$tmp_dir/kis-project"
mkdir -p "$kis_root/kis/state"
printf 'Branch: main\nTask: wire commands\nNext: run tests\n' > "$kis_root/kis/state/current.md"
anchor_output="$("$hook_script" "$kis_root")"
[[ "$anchor_output" == *"Task: wire commands"* ]] || fail "hook did not print State"
[[ "$anchor_output" == *"/kis:start"* ]] || fail "hook did not print the command list"

empty_output="$("$hook_script" "$tmp_dir/no-kis")"
[[ "$empty_output" == *"not initialized"* ]] || fail "hook did not handle a project without kis/"

# The Antigravity hook sends the anchor as an ephemeral message (agy drops it after the turn) at the
# first invocation of every turn, and prints {} without running the anchor on the other calls.
json_field() {  # <json> <ruby expression on d>
  ruby -rjson -e 'd = JSON.parse(ARGV[0]); print(eval(ARGV[1]))' "$1" "$2"
}

marker_home="$tmp_dir/hook-markers"
mkdir -p "$marker_home"
agy_payload() {  # <conversation id> <invocationNum or "none">
  if [[ "$2" == none ]]; then
    printf '{"conversationId":"%s","workspacePaths":["%s"]}' "$1" "$kis_root"
  else
    printf '{"conversationId":"%s","workspacePaths":["%s"],"invocationNum":%s,"initialNumSteps":4}' "$1" "$kis_root" "$2"
  fi
}
agy_run() { TMPDIR="$marker_home" "$antigravity_hook_script"; }
antigravity_output="$(agy_payload conv-1 0 | agy_run)"
[[ "$antigravity_output" == *'"injectSteps"'* ]] || fail "Antigravity hook did not inject a step"
[[ "$antigravity_output" == *"Task: wire commands"* ]] || fail "Antigravity hook did not inject State"
[[ "$(json_field "$antigravity_output" 'd["injectSteps"].map { |s| s.keys.join }.join(",")')" == "ephemeralMessage" ]] || fail "Antigravity step is not exactly one ephemeralMessage: $antigravity_output"
[[ "$(json_field "$antigravity_output" 'd["injectSteps"][0]["ephemeralMessage"].chomp')" == "$("$hook_script" "$kis_root")" ]] || fail "Antigravity ephemeralMessage is not the anchor text"
[[ "$(agy_payload conv-0 0 | agy_run)" == *'"injectSteps"'* ]] || fail "Antigravity hook did not inject at invocationNum 0"
# Live check (agy 1.4.0): invocationNum is a number, 0 for the first call of a turn, 1, 2 ... after it.
for n in 1 2 3 40; do
  [[ "$(agy_payload conv-1 "$n" | agy_run)" == "{}" ]] || fail "Antigravity hook injected at invocationNum $n of the same turn"
done
[[ "$(printf '{"conversationId":"conv-1","workspacePaths":["%s"],"invocationNum":"3"}' "$kis_root" | agy_run)" == "{}" ]] || fail "Antigravity hook injected at a string invocationNum 3"
# Values that are not the integer 0 are not a first call: a non-integer string, a float, a boolean, a list.
for odd in '"2.0"' '1e1' '0.5' 'true' '[2]' '"abc"' '"1"'; do
  [[ "$(agy_payload conv-1 "$odd" | agy_run)" == "{}" ]] || fail "Antigravity hook injected at invocationNum $odd"
done
[[ "$(agy_payload conv-1 '"0"' | agy_run)" == *'"injectSteps"'* ]] || fail "Antigravity hook did not inject at the string invocationNum 0"
# The next turn is anchored again with the State as it is then, changed or not.
[[ "$(agy_payload conv-1 0 | agy_run)" == *"Task: wire commands"* ]] || fail "Antigravity hook did not re-anchor the next turn"
printf 'Branch: main\nTask: wire commands, then ship\nNext: run tests\n' > "$kis_root/kis/state/current.md"
[[ "$(agy_payload conv-1 2 | agy_run)" == "{}" ]] || fail "Antigravity hook re-injected changed State mid-turn"
changed_output="$(agy_payload conv-1 0 | agy_run)"
[[ "$changed_output" == *"Task: wire commands, then ship"* ]] || fail "Antigravity hook did not carry the current State into the next turn: $changed_output"
printf 'Branch: main\nTask: wire commands\nNext: run tests\n' > "$kis_root/kis/state/current.md"
# A payload with no invocationNum is treated as a first call, so the anchor is never lost.
[[ "$(agy_payload conv-2 none | agy_run)" == *'"injectSteps"'* ]] || fail "Antigravity hook did not inject without an invocationNum"
garbage_output="$(printf 'not json' | agy_run)"
[[ "$garbage_output" == *'"injectSteps"'* || "$garbage_output" == "{}" ]] || fail "Antigravity hook did not emit JSON for an unparsable payload"
# Nothing is kept between calls: no marker directory, no files.
[[ -z "$(ls -A "$marker_home")" ]] || fail "Antigravity hook left files in TMPDIR: $(ls -A "$marker_home")"
# Calls after the first of a turn must not run the anchor at all (the cost finding): a counting anchor.
counted="$tmp_dir/counted-hooks"; mkdir -p "$counted"
cp "$antigravity_hook_script" "$counted/antigravity-anchor.sh"
printf '#!/usr/bin/env bash\necho run >> "%s/runs"\necho anchor text\n' "$counted" > "$counted/session-anchor.sh"
chmod +x "$counted/antigravity-anchor.sh" "$counted/session-anchor.sh"
for n in 0 1 2 3 4; do agy_payload conv-count "$n" | "$counted/antigravity-anchor.sh" >/dev/null; done
[[ "$(wc -l < "$counted/runs" | tr -d ' ')" == "1" ]] || fail "Antigravity hook ran the anchor on calls after the first of a turn: $(wc -l < "$counted/runs") runs for 5 calls"

# The Command Code adapter wraps the anchor in cmd's SessionStart JSON shape, and degrades to {}.
expected_anchor="$("$hook_script" "$kis_root")"
cmd_output="$(printf '{"hook_event_name":"SessionStart","source":"startup","cwd":"%s"}' "$kis_root" | "$cmd_hook_script")"
[[ "$(json_field "$cmd_output" 'd.keys.join(",")')" == "hookSpecificOutput" ]] || fail "cmd adapter output has the wrong top-level keys: $cmd_output"
[[ "$(json_field "$cmd_output" 'd["hookSpecificOutput"].keys.sort.join(",")')" == "additionalContext,hookEventName" ]] || fail "cmd adapter output has the wrong fields: $cmd_output"
[[ "$(json_field "$cmd_output" 'd["hookSpecificOutput"]["hookEventName"]')" == "SessionStart" ]] || fail "cmd adapter hookEventName is wrong"
[[ "$(json_field "$cmd_output" 'd["hookSpecificOutput"]["additionalContext"].chomp')" == "$expected_anchor" ]] || fail "cmd adapter additionalContext is not the anchor text"
arg_output="$(printf 'not json' | "$cmd_hook_script" "$kis_root")"
[[ "$(json_field "$arg_output" 'd["hookSpecificOutput"]["additionalContext"].chomp')" == "$expected_anchor" ]] || fail "cmd adapter ignored its root argument for an unparsable payload"
broken_hooks="$tmp_dir/broken-hooks"; mkdir -p "$broken_hooks"
cp "$cmd_hook_script" "$broken_hooks/cmd-anchor.sh"; cp "$hook_script" "$broken_hooks/session-anchor.sh"
printf '#!/usr/bin/env bash\necho partial anchor text\nexit 3\n' > "$broken_hooks/session-anchor.sh"; chmod +x "$broken_hooks/session-anchor.sh" "$broken_hooks/cmd-anchor.sh"
[[ "$("$broken_hooks/cmd-anchor.sh" "$kis_root" < /dev/null)" == "{}" ]] || fail "cmd adapter did not print {} when the anchor failed"
rm -f "$broken_hooks/session-anchor.sh"
[[ "$("$broken_hooks/cmd-anchor.sh" "$kis_root" < /dev/null)" == "{}" ]] || fail "cmd adapter did not print {} when the anchor is missing"

# Commands KIS shipped in earlier releases (the first one is from 44a7099, the second from 40c2911).
old_codex_1='root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; h="$root/.agents/skills/kis/hooks/session-anchor.sh"; [ -x "$h" ] && exec "$h" "$root"; exit 0'
old_codex_2='d=$PWD; while :; do h="$d/.agents/skills/kis/hooks/session-anchor.sh"; [ -x "$h" ] && exec "$h" "$d"; [ "$d" = / ] && exit 0; d=$(dirname "$d"); done'
old_cmd_1='root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; h="$root/.agents/skills/kis/hooks/cmd-anchor.sh"; [ -x "$h" ] && exec "$h" "$root"; exit 0'
old_cmd_2='d=$PWD; while :; do h="$d/.agents/skills/kis/hooks/cmd-anchor.sh"; [ -x "$h" ] && exec "$h" "$d"; [ "$d" = / ] && exit 0; d=$(dirname "$d"); done'
# The installed Codex and Command Code commands, run the way the hosts run them: from a subdirectory
# of the repo, from a directory that is not a repo, and in a project without the package.
live="$tmp_dir/live"; mkdir -p "$live/.agents/skills" "$live/src/deep" "$live/kis/state"
cp -R "$package_dir" "$live/.agents/skills/kis"
printf 'Branch: main\nTask: wire commands\nNext: run tests\n' > "$live/kis/state/current.md"
git -C "$live" init -q -b main 2>/dev/null || true
"$script_under_test" --target "$live" --no-instructions >/dev/null
codex_cmd="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).dig("hooks","SessionStart").flat_map { |e| e["hooks"] }.map { |h| h["command"] }.grep(/session-anchor/).first' "$live/.codex/hooks.json")"
cmd_cmd="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).dig("hooks","SessionStart").flat_map { |e| e["hooks"] }.map { |h| h["command"] }.grep(/cmd-anchor/).first' "$live/.commandcode/settings.json")"
codex_out="$(cd "$live/src/deep" && sh -c "$codex_cmd" < /dev/null)"
[[ "$codex_out" == "$("$hook_script" "$live")" && "$codex_out" == *"Task: wire commands"* ]] || fail "Codex command from a subdirectory did not print the anchor: $codex_out"
cmd_out="$(cd "$live/src/deep" && sh -c "$cmd_cmd" < /dev/null)"
[[ "$(json_field "$cmd_out" 'd["hookSpecificOutput"]["additionalContext"].chomp')" == "$("$hook_script" "$live")" ]] || fail "cmd command from a subdirectory did not print the anchor JSON: $cmd_out"
bare="$tmp_dir/bare"; mkdir -p "$bare"
[[ -z "$(cd "$bare" && sh -c "$codex_cmd" < /dev/null)" ]] || fail "Codex command printed something in a project without the package"
[[ -z "$(cd "$bare" && sh -c "$cmd_cmd" < /dev/null)" ]] || fail "cmd command printed something in a project without the package"
rc=0; (cd "$bare" && sh -c "$codex_cmd" < /dev/null >/dev/null 2>&1) || rc=$?; [[ "$rc" == 0 ]] || fail "Codex command failed (exit $rc) in a project without the package"
rc=0; (cd "$bare" && sh -c "$cmd_cmd" < /dev/null >/dev/null 2>&1) || rc=$?; [[ "$rc" == 0 ]] || fail "cmd command failed (exit $rc) in a project without the package"

# The hosts kill a hook at its timeout. With a git that hangs, the stamp check gives up at its own cap
# and the anchor still arrives whole, inside that timeout.
if command -v timeout >/dev/null 2>&1; then
  slowproj="$tmp_dir/slow-project"; mkdir -p "$slowproj/.agents/skills"; cp -R "$live/.agents/skills/kis" "$slowproj/.agents/skills/kis"
  mkdir -p "$slowproj/kis/state"
  printf 'Stamp: main abc1234 000000000000\nBranch: main\nTask: wire commands\nNext: run tests\n' > "$slowproj/kis/state/current.md"
  "$script_under_test" --target "$slowproj" --no-instructions >/dev/null
  slow_git="$tmp_dir/slow-git"; mkdir -p "$slow_git"
  printf '#!/bin/sh\nsleep 60\n' > "$slow_git/git"; chmod +x "$slow_git/git"
  for host in "codex|$slowproj/.codex/hooks.json|session-anchor" "cmd|$slowproj/.commandcode/settings.json|cmd-anchor"; do
    IFS='|' read -r hname hfile hmarker <<< "$host"
    hcmd="$(read_cmd "$hfile" "$hmarker")"; htimeout="$(read_timeout "$hfile" "$hmarker")"
    t0="$(date +%s)"; rc=0
    hout="$(cd "$slowproj" && PATH="$slow_git:$PATH" timeout "$htimeout" sh -c "$hcmd" < /dev/null 2>/dev/null)" || rc=$?
    t1="$(date +%s)"
    [[ "$rc" == 0 && "$hout" == *"Task: wire commands"* ]] || fail "$hname hook with a hanging git: exit $rc inside its ${htimeout}s timeout, output: $hout"
    [[ "$hout" != *"Stale State"* ]] || fail "$hname hook with a hanging git still reported Stale State"
    echo "($hname hook with a hanging git: full anchor after $(( t1 - t0 )) s of its ${htimeout} s timeout)"
  done
else
  echo "(timeout absent: the slow-stamp hook case was not run)"
fi

# The cmd adapter prints {} and stays quiet on stderr for each way it can fail: an anchor that is not
# executable, an error inside the adapter (a NUL byte in the root makes popen raise), and a ruby that
# itself exits non-zero.
noexec_hooks="$tmp_dir/noexec-hooks"; mkdir -p "$noexec_hooks"
cp "$cmd_hook_script" "$noexec_hooks/cmd-anchor.sh"; cp "$hook_script" "$noexec_hooks/session-anchor.sh"
chmod -x "$noexec_hooks/session-anchor.sh"; chmod +x "$noexec_hooks/cmd-anchor.sh"
out="$("$noexec_hooks/cmd-anchor.sh" "$kis_root" < /dev/null 2>"$tmp_dir/noexec.err")"
[[ "$out" == "{}" && ! -s "$tmp_dir/noexec.err" ]] || fail "cmd adapter with a non-executable anchor: stdout '$out', stderr '$(cat "$tmp_dir/noexec.err")'"
out="$(printf '{"cwd":"a\\u0000b"}' | "$cmd_hook_script" 2>"$tmp_dir/raise.err")"
[[ "$out" == "{}" && ! -s "$tmp_dir/raise.err" ]] || fail "cmd adapter did not swallow its own error quietly: stdout '$out', stderr '$(cat "$tmp_dir/raise.err")'"
fake_bin="$tmp_dir/fake-ruby"; mkdir -p "$fake_bin"
printf '#!/bin/sh\nexit 1\n' > "$fake_bin/ruby"; chmod +x "$fake_bin/ruby"
rc=0; out="$(PATH="$fake_bin:$PATH" "$cmd_hook_script" "$kis_root" < /dev/null 2>/dev/null)" || rc=$?
[[ "$out" == "{}" && "$rc" == 0 ]] || fail "cmd adapter did not fall back to {} (exit $rc) when ruby fails: '$out'"

# No locale and a State with an em dash and a stray invalid byte: both adapters still carry the anchor.
enc_root="$tmp_dir/enc-project"; mkdir -p "$enc_root/kis/state"
printf -- '- Branch: main\n- Task: ship it \xe2\x80\x94 today \xc3\xa9, bad \xff\xfe byte\n- Next: go\n' > "$enc_root/kis/state/current.md"
dash="$(printf '\xe2\x80\x94')"; repl="$(printf '\xef\xbf\xbd')"
enc_cmd="$(printf '{"cwd":"%s"}' "$enc_root" | env -u LANG -u LC_ALL -u LC_CTYPE "$cmd_hook_script")"
[[ "$enc_cmd" == *'"hookSpecificOutput"'* && "$enc_cmd" == *"Task: ship it $dash today"* && "$enc_cmd" == *"bad $repl"*"byte"* ]] || fail "cmd adapter lost a non-ASCII State without a locale: $enc_cmd"
enc_agy="$(printf '{"conversationId":"enc","workspacePaths":["%s"],"invocationNum":0}' "$enc_root" | env -u LANG -u LC_ALL -u LC_CTYPE TMPDIR="$marker_home" "$antigravity_hook_script")"
[[ "$enc_agy" == *'"injectSteps"'* && "$enc_agy" == *"Task: ship it $dash today"* && "$enc_agy" == *"bad $repl"*"byte"* ]] || fail "Antigravity hook lost a non-ASCII State without a locale: $enc_agy"
enc_c="$(printf '{"cwd":"%s"}' "$enc_root" | env LC_ALL=C "$cmd_hook_script")"
[[ "$enc_c" == *"Task: ship it $dash today"* ]] || fail "cmd adapter lost a non-ASCII State under LC_ALL=C: $enc_c"

# A KIS project below the git root, an outer project holding another copy, and a project with no git
# at all, each started from a subdirectory: the hook walks up to the nearest package.
mono="$tmp_dir/mono repo"; inner="$mono/pkg a"
mkdir -p "$inner/src/deep" "$inner/.agents/skills" "$inner/kis/state" "$mono/.agents/skills" "$mono/kis/state"
git -C "$mono" init -q -b main 2>/dev/null || true
cp -R "$package_dir" "$inner/.agents/skills/kis"; cp -R "$package_dir" "$mono/.agents/skills/kis"
printf 'Branch: main\nTask: inner project\nNext: go\n' > "$inner/kis/state/current.md"
printf 'Branch: main\nTask: outer project\nNext: go\n' > "$mono/kis/state/current.md"
"$script_under_test" --target "$inner" --no-instructions >/dev/null
inner_codex="$(read_cmd "$inner/.codex/hooks.json" session-anchor)"; inner_cmd="$(read_cmd "$inner/.commandcode/settings.json" cmd-anchor)"
for shell in sh /bin/bash; do
  out="$(cd "$inner/src/deep" && $shell -c "$inner_codex" < /dev/null)"
  [[ "$out" == "$("$hook_script" "$inner")" && "$out" == *"Task: inner project"* ]] || fail "Codex command ($shell) in a project below the git root printed: $out"
  out="$(cd "$inner" && $shell -c "$inner_codex" < /dev/null)"
  [[ "$out" == *"Task: inner project"* ]] || fail "Codex command ($shell) at the project root printed: $out"
  out="$(cd "$inner/src/deep" && $shell -c "$inner_cmd" < /dev/null)"
  [[ "$(json_field "$out" 'd["hookSpecificOutput"]["additionalContext"].chomp')" == "$("$hook_script" "$inner")" ]] || fail "cmd command ($shell) in a project below the git root printed: $out"
done
nogit="$tmp_dir/no git"; mkdir -p "$nogit/src" "$nogit/.agents/skills" "$nogit/kis/state"
cp -R "$package_dir" "$nogit/.agents/skills/kis"; printf 'Branch: main\nTask: no git project\nNext: go\n' > "$nogit/kis/state/current.md"
out="$(cd "$nogit/src" && sh -c "$inner_codex" < /dev/null)"
[[ "$out" == *"Task: no git project"* ]] || fail "Codex command in a project with no git, from a subdirectory, printed: $out"

# Re-installing refreshes a command that is out of date, and says to trust it again.
stale="$tmp_dir/stale"; "$script_under_test" --target "$stale" --no-instructions >/dev/null
set_hook "$stale/.codex/hooks.json" session-anchor "$old_codex_1" 10
set_hook "$stale/.commandcode/settings.json" cmd-anchor "$old_cmd_2" 10
stale_check="$("$script_under_test" --target "$stale" --check)"
[[ "$(grep -c '^Codex SessionStart hook: installed, but its command is outdated' <<< "$stale_check")" == "1" ]] || fail "--check did not flag the stale Codex command: $stale_check"
[[ "$(grep -c '^Command Code SessionStart hook: installed, but its command is outdated' <<< "$stale_check")" == "1" ]] || fail "--check did not flag the stale cmd command: $stale_check"
refresh_out="$("$script_under_test" --target "$stale" --no-instructions)"
[[ "$(grep -c '^Codex SessionStart hook: refreshed in ' <<< "$refresh_out")" == "1" ]] || fail "stale Codex command was not refreshed: $refresh_out"
[[ "$(grep -c '^Command Code SessionStart hook: refreshed in ' <<< "$refresh_out")" == "1" ]] || fail "stale cmd command was not refreshed: $refresh_out"
[[ "$(grep -c '^Codex: run /hooks once and trust the KIS SessionStart hook\.' <<< "$refresh_out")" == "1" ]] || fail "refresh did not repeat the Codex trust step: $refresh_out"
grep -q 'git rev-parse' "$stale/.codex/hooks.json" "$stale/.commandcode/settings.json" && fail "a stale command survived the refresh"
grep -q 'while :; do' "$stale/.codex/hooks.json" || fail "the refreshed Codex entry lost its command"
[[ "$(read_cmd "$stale/.codex/hooks.json" session-anchor)" == "$inner_codex" ]] || fail "refreshed Codex command is not the current one"
[[ "$(count_marker "$stale/.codex/hooks.json" kis/hooks/session-anchor.sh)" == "1" && "$(count_marker "$stale/.commandcode/settings.json" kis/hooks/cmd-anchor.sh)" == "1" ]] || fail "refresh duplicated an entry"
[[ "$("$script_under_test" --target "$stale" --no-instructions | grep -c 'already installed$')" == "4" ]] || fail "a refreshed project did not settle to already installed"

# Every command an earlier KIS shipped is refreshed, one fresh project per command.
for i in 1 2 3 4; do
  case $i in
    1) oname=codex; omarker=session-anchor; ofile=.codex/hooks.json; ocmd="$old_codex_1"; ocur="$inner_codex" ;;
    2) oname=codex; omarker=session-anchor; ofile=.codex/hooks.json; ocmd="$old_codex_2"; ocur="$inner_codex" ;;
    3) oname=cmd; omarker=cmd-anchor; ofile=.commandcode/settings.json; ocmd="$old_cmd_1"; ocur="$inner_cmd" ;;
    4) oname=cmd; omarker=cmd-anchor; ofile=.commandcode/settings.json; ocmd="$old_cmd_2"; ocur="$inner_cmd" ;;
  esac
  op="$tmp_dir/old-$oname"; rm -rf "$op"; "$script_under_test" --target "$op" --no-instructions >/dev/null
  set_hook "$op/$ofile" "$omarker" "$ocmd" 10
  out="$("$script_under_test" --target "$op" --no-instructions)"
  [[ "$out" == *"SessionStart hook: refreshed in"* ]] || fail "an old $oname command ($ocmd) was not refreshed: $out"
  [[ "$(read_cmd "$op/$ofile" "$omarker")" == "$ocur" ]] || fail "an old $oname command ($ocmd) was refreshed to something else"
done

# Hook timeout: a fresh entry carries 20 s (the stamp check inside the anchor is capped at 5 s). A stock
# entry that still carries the old 10 is raised to 20, and a timeout the user set is kept.
[[ "$(read_timeout "$stale/.codex/hooks.json" session-anchor)" == "20" && "$(read_timeout "$stale/.commandcode/settings.json" cmd-anchor)" == "20" ]] || fail "a refreshed entry did not get the 20 s timeout"
t="$tmp_dir/timeouts"; "$script_under_test" --target "$t" --no-instructions >/dev/null
[[ "$(read_timeout "$t/.codex/hooks.json" session-anchor)" == "20" && "$(read_timeout "$t/.commandcode/settings.json" cmd-anchor)" == "20" ]] || fail "a fresh entry does not carry the 20 s timeout"
set_hook "$t/.codex/hooks.json" session-anchor "$inner_codex" 10; set_hook "$t/.commandcode/settings.json" cmd-anchor "$inner_cmd" 10
out="$("$script_under_test" --target "$t" --no-instructions --check)"
[[ "$(grep -c 'but its timeout is outdated' <<< "$out")" == "2" && "$out" != *'command is outdated'* ]] || fail "--check did not name the old timeout 10 of the stock command: $out"
"$script_under_test" --target "$t" --no-instructions >/dev/null
[[ "$(read_timeout "$t/.codex/hooks.json" session-anchor)" == "20" && "$(read_timeout "$t/.commandcode/settings.json" cmd-anchor)" == "20" ]] || fail "the stock command with timeout 10 was not raised to 20"
set_hook "$t/.codex/hooks.json" session-anchor "$old_codex_1" 30; set_hook "$t/.commandcode/settings.json" cmd-anchor "$old_cmd_1" none
"$script_under_test" --target "$t" --no-instructions >/dev/null
[[ "$(read_cmd "$t/.codex/hooks.json" session-anchor)" == "$inner_codex" && "$(read_timeout "$t/.codex/hooks.json" session-anchor)" == "30" ]] || fail "a refresh replaced a timeout the user had set"
[[ "$(read_cmd "$t/.commandcode/settings.json" cmd-anchor)" == "$inner_cmd" && "$(read_timeout "$t/.commandcode/settings.json" cmd-anchor)" == "nil" ]] || fail "a refresh added a timeout the user had removed"

# A command the user changed (it still holds the marker) is neither reported as outdated nor rewritten.
cu="$tmp_dir/custom"; "$script_under_test" --target "$cu" --no-instructions >/dev/null
set_hook "$cu/.codex/hooks.json" session-anchor "KIS_ANCHOR_MAX_LINES=30 $inner_codex" 30
set_hook "$cu/.commandcode/settings.json" cmd-anchor "my-wrapper.sh && .agents/skills/kis/hooks/cmd-anchor.sh" 20
cp "$cu/.codex/hooks.json" "$tmp_dir/custom-codex.json"; cp "$cu/.commandcode/settings.json" "$tmp_dir/custom-cmd.json"
out="$("$script_under_test" --target "$cu" --no-instructions --check)"
[[ "$(grep -c '^Codex SessionStart hook: installed, customised, left alone$' <<< "$out")" == "1" && "$(grep -c '^Command Code SessionStart hook: installed, customised, left alone$' <<< "$out")" == "1" ]] || fail "--check did not report the customised entries: $out"
out="$("$script_under_test" --target "$cu" --no-instructions)"
[[ "$(grep -c '^Codex SessionStart hook: customised, left alone$' <<< "$out")" == "1" && "$(grep -c '^Command Code SessionStart hook: customised, left alone$' <<< "$out")" == "1" ]] || fail "install did not report the customised entries: $out"
[[ "$out" != *"Codex SessionStart hook: refreshed"* && "$out" != *"Command Code SessionStart hook: refreshed"* && "$out" != *"trust the KIS SessionStart hook"* ]] || fail "install refreshed a customised entry: $out"
cmp -s "$cu/.codex/hooks.json" "$tmp_dir/custom-codex.json" && cmp -s "$cu/.commandcode/settings.json" "$tmp_dir/custom-cmd.json" || fail "install rewrote a customised entry"
# One stock-old entry beside a customised one: the old one is refreshed, the customised one stays.
ruby -rjson -e 'p = ARGV[0]; d = JSON.parse(File.read(p)); d["hooks"]["SessionStart"] << { "hooks" => [{ "type" => "command", "command" => ARGV[1], "timeout" => 10 }] }; File.write(p, JSON.pretty_generate(d) + "\n")' "$cu/.codex/hooks.json" "$old_codex_1"
out="$("$script_under_test" --target "$cu" --no-instructions)"
[[ "$out" == *"Codex SessionStart hook: refreshed in"* && "$out" == *"customised entry left alone"* ]] || fail "a mixed file was not handled: $out"
[[ "$(count_marker "$cu/.codex/hooks.json" 'KIS_ANCHOR_MAX_LINES=30')" == "1" ]] || fail "the customised entry was lost in a mixed file"

# The backup is the pre-install copy and stays that way: not rewritten by a re-install, a refresh or
# a remove, and not made for a file that has no KIS entry yet to protect.
bk="$tmp_dir/backup-project"; mkdir -p "$bk/.codex" "$bk/.agents" "$bk/.claude"
cp "$tmp_dir/codex-original.json" "$bk/.codex/hooks.json"
printf '{"existing-guard":{"PreToolUse":[]}}\n' > "$bk/.agents/hooks.json"
printf '{"permissions":{"allow":["Bash(ls:*)"]}}\n' > "$bk/.claude/settings.json"
for f in .codex/hooks.json .agents/hooks.json .claude/settings.json; do cp "$bk/$f" "$tmp_dir/orig-$(basename "$f")-$(dirname "$f" | tr -d .)"; done
"$script_under_test" --target "$bk" --no-instructions >/dev/null
"$script_under_test" --target "$bk" --no-instructions >/dev/null
set_hook "$bk/.codex/hooks.json" session-anchor "$old_codex_2" 10
"$script_under_test" --target "$bk" --no-instructions >/dev/null
for f in .codex/hooks.json .agents/hooks.json .claude/settings.json; do
  cmp -s "$bk/$f.kis-bak" "$tmp_dir/orig-$(basename "$f")-$(dirname "$f" | tr -d .)" || fail "$f.kis-bak is not the pre-install copy after install, re-install and refresh"
done
[[ ! -e "$bk/.commandcode/settings.json.kis-bak" ]] || fail "a backup was written for a Command Code file that did not exist"
# A remove hands the files back as the user's own, so their backups go with it; a later install takes a
# fresh backup of the file as it is then.
"$script_under_test" --target "$bk" --remove --no-instructions >/dev/null
for f in .codex/hooks.json .agents/hooks.json .claude/settings.json; do
  [[ ! -e "$bk/$f.kis-bak" ]] || fail "$f.kis-bak outlived --remove"
done
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash edited-after.sh"}]}]}}\n' > "$bk/.codex/hooks.json"
cp "$bk/.codex/hooks.json" "$tmp_dir/edited-after.json"
"$script_under_test" --target "$bk" --no-instructions >/dev/null
cmp -s "$bk/.codex/hooks.json.kis-bak" "$tmp_dir/edited-after.json" || fail "a re-install after --remove did not back up the file as it then was"

# A file KIS created after an earlier remove goes away with its entry: no stale backup makes it look
# like the user's.
sb="$tmp_dir/stale-backup"; rm -rf "$sb"; mkdir -p "$sb/.codex" "$sb/.agents" "$sb/.claude" "$sb/.commandcode"
printf '{"model":"m"}\n' > "$sb/.codex/hooks.json"; printf '{"model":"m"}\n' > "$sb/.commandcode/settings.json"
printf '{"model":"m"}\n' > "$sb/.claude/settings.json"; printf '{"existing-guard":{}}\n' > "$sb/.agents/hooks.json"
"$script_under_test" --target "$sb" --no-instructions >/dev/null
"$script_under_test" --target "$sb" --remove --no-instructions >/dev/null
for f in .codex/hooks.json .agents/hooks.json .claude/settings.json .commandcode/settings.json; do rm -f "$sb/$f"; done
"$script_under_test" --target "$sb" --no-instructions >/dev/null
"$script_under_test" --target "$sb" --remove --no-instructions >/dev/null
for f in .codex/hooks.json .agents/hooks.json .claude/settings.json .commandcode/settings.json; do
  [[ ! -e "$sb/$f" && ! -e "$sb/$f.kis-bak" ]] || fail "install, remove, delete, install, remove left $f or its backup behind: $(cat "$sb/$f" 2>/dev/null)"
done

# A customised Antigravity entry is left alone like the Codex and Command Code ones; a stock one is not rewritten.
ag="$tmp_dir/agy-custom"; rm -rf "$ag"; "$script_under_test" --target "$ag" --no-instructions >/dev/null
out="$("$script_under_test" --target "$ag" --no-instructions)"
[[ "$(grep -c '^Antigravity PreInvocation hook: already installed$' <<< "$out")" == "1" ]] || fail "a stock Antigravity entry was not reported as already installed: $out"
ruby -rjson -e 'p = ARGV[0]; d = JSON.parse(File.read(p)); h = d["kis-anchor"]["PreInvocation"][0]; h["command"] = "KIS_ANCHOR_MAX_LINES=30 " + h["command"]; h["timeout"] = 40; File.write(p, JSON.pretty_generate(d) + "\n")' "$ag/.agents/hooks.json"
cp "$ag/.agents/hooks.json" "$tmp_dir/agy-custom.json"
out="$("$script_under_test" --target "$ag" --no-instructions --check)"
[[ "$(grep -c '^Antigravity PreInvocation hook: installed, customised, left alone$' <<< "$out")" == "1" ]] || fail "--check did not report the customised Antigravity entry: $out"
out="$("$script_under_test" --target "$ag" --no-instructions)"
[[ "$(grep -c '^Antigravity PreInvocation hook: customised, left alone$' <<< "$out")" == "1" ]] || fail "install did not report the customised Antigravity entry: $out"
cmp -s "$ag/.agents/hooks.json" "$tmp_dir/agy-custom.json" || fail "install rewrote a customised Antigravity entry"
# A stock entry whose spelling no longer fits (the project moved, or the file is named another way) is refreshed.
mv_w="$tmp_dir/agy-moved"; rm -rf "$mv_w"; mkdir -p "$mv_w/old"
"$script_under_test" --target "$mv_w/old" --hooks-json "$mv_w/old/.gemini/hooks.json" --no-instructions >/dev/null
mv "$mv_w/old" "$mv_w/new"
out="$("$script_under_test" --target "$mv_w/new" --hooks-json "$mv_w/new/.gemini/hooks.json" --no-instructions --check)"
[[ "$(grep -c '^Antigravity PreInvocation hook: installed, but its command is outdated' <<< "$out")" == "1" ]] || fail "--check did not flag the Antigravity entry of a moved project: $out"
out="$("$script_under_test" --target "$mv_w/new" --hooks-json "$mv_w/new/.gemini/hooks.json" --no-instructions)"
[[ "$(grep -c '^Antigravity PreInvocation hook: refreshed in ' <<< "$out")" == "1" ]] || fail "the Antigravity entry of a moved project was not refreshed: $out"
[[ "$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["kis-anchor"]["PreInvocation"][0]["command"]' "$mv_w/new/.gemini/hooks.json")" == "$(cd "$mv_w/new" && pwd -P)/.agents/skills/kis/hooks/antigravity-anchor.sh" ]] || fail "the moved project's Antigravity command was not rewritten to the new path"
mv_p="$tmp_dir/agy-spelling"; rm -rf "$mv_p"; "$script_under_test" --target "$mv_p" --no-instructions >/dev/null
out="$(cd "$mv_p" && "$script_under_test" --target . --hooks-json .agents/hooks.json --no-instructions)"
[[ "$out" != *"Antigravity PreInvocation hook: customised"* ]] || fail "an entry KIS just wrote was called customised under another spelling: $out"
out="$(cd "$mv_p" && "$script_under_test" --target . --hooks-json .agents/hooks.json --no-instructions)"
[[ "$(grep -c '^Antigravity PreInvocation hook: already installed$' <<< "$out")" == "1" ]] || fail "the other spelling of the same hooks file was not reported as already installed: $out"
out="$("$script_under_test" --target "$mv_p" --hooks-json "$mv_p/.agents/hooks.json" --no-instructions)"
[[ "$(grep -c '^Antigravity PreInvocation hook: already installed$' <<< "$out")" == "1" ]] || fail "the absolute spelling of the same hooks file was not reported as already installed: $out"
# A wrapper around the script, or a live absolute path to another package, is the user's and stays.
for cmd in "/usr/bin/env KIS_ANCHOR_MAX_LINES=40 $tmp_dir/x/.agents/skills/kis/hooks/antigravity-anchor.sh" "$tmp_dir/other-pkg/.agents/skills/kis/hooks/antigravity-anchor.sh"; do
  ow="$tmp_dir/agy-own"; rm -rf "$ow" "$tmp_dir/other-pkg"; mkdir -p "$ow/.agents" "$tmp_dir/other-pkg/.agents/skills/kis/hooks"
  : > "$tmp_dir/other-pkg/.agents/skills/kis/hooks/antigravity-anchor.sh"
  ruby -rjson -e 'File.write(ARGV[0], JSON.generate({"kis-anchor"=>{"PreInvocation"=>[{"type"=>"command","command"=>ARGV[1],"timeout"=>15}]}}) + "\n")' "$ow/.agents/hooks.json" "$cmd"
  cp "$ow/.agents/hooks.json" "$tmp_dir/agy-own.json"
  out="$("$script_under_test" --target "$ow" --no-instructions)"
  [[ "$(grep -c '^Antigravity PreInvocation hook: customised, left alone$' <<< "$out")" == "1" ]] || fail "install did not leave alone the Antigravity command '$cmd': $out"
  cmp -s "$ow/.agents/hooks.json" "$tmp_dir/agy-own.json" || fail "install rewrote the Antigravity command '$cmd'"
done

# A backup left by an earlier install does not outlive the KIS entry it protected: with no KIS entry the
# file on disk is the user's current copy, so a file KIS creates later still goes away with its entry.
sb2="$tmp_dir/stale-backup2"; rm -rf "$sb2"; mkdir -p "$sb2/.codex"
printf '{"model":"m"}\n' > "$sb2/.codex/hooks.json"
"$script_under_test" --target "$sb2" --no-instructions >/dev/null
printf '{"model":"m"}\n' > "$sb2/.codex/hooks.json"
"$script_under_test" --target "$sb2" --no-instructions --remove >/dev/null
rm "$sb2/.codex/hooks.json"
"$script_under_test" --target "$sb2" --no-instructions >/dev/null
"$script_under_test" --target "$sb2" --no-instructions --remove >/dev/null
[[ ! -e "$sb2/.codex/hooks.json" && ! -e "$sb2/.codex/hooks.json.kis-bak" ]] || fail "a stale backup left {} behind after install and remove: $(cat "$sb2/.codex/hooks.json" 2>/dev/null)"

# A hook file the user deleted after install leaves its pre-install backup in place, renamed, when KIS installs again.
pc="$tmp_dir/precious"; rm -rf "$pc"; mkdir -p "$pc/.codex"
printf '{"model":"precious"}\n' > "$pc/.codex/hooks.json"
"$script_under_test" --target "$pc" --no-instructions >/dev/null
rm "$pc/.codex/hooks.json"
"$script_under_test" --target "$pc" --no-instructions >/dev/null
[[ "$(grep -l '^{"model":"precious"}$' "$pc"/.codex/hooks.json.kis-bak.* 2>/dev/null | wc -l | tr -d ' ')" == "1" ]] || fail "the only copy of the user's file was not kept when the file was deleted: $(ls -A "$pc/.codex")"
[[ ! -e "$pc/.codex/hooks.json.kis-bak" ]] || fail "a backup of a file KIS created was kept under the plain name"

# A symlink left at the backup name is replaced, never written through.
sl="$tmp_dir/bak-symlink"; rm -rf "$sl"; mkdir -p "$sl/.codex"
printf '{"model":"m"}\n' > "$sl/.codex/hooks.json"; printf 'elsewhere\n' > "$sl/elsewhere"
ln -s ../elsewhere "$sl/.codex/hooks.json.kis-bak"
"$script_under_test" --target "$sl" --no-instructions >/dev/null
[[ "$(cat "$sl/elsewhere")" == "elsewhere" ]] || fail "the backup was written through a symlink: $(cat "$sl/elsewhere")"
[[ ! -L "$sl/.codex/hooks.json.kis-bak" && "$(cat "$sl/.codex/hooks.json.kis-bak")" == '{"model":"m"}' ]] || fail "the symlink at the backup name was not replaced by the backup"

# A --hooks-json path starting with ~ is a relative name, not a home directory: no Ruby error.
tl="$tmp_dir/tilde"; rm -rf "$tl"; mkdir -p "$tl/cwd"
err="$(cd "$tl/cwd" && "$script_under_test" --target "$tl" --hooks-json '~nouser/hooks.json' --no-instructions 2>&1 >/dev/null)"
[[ -z "$err" ]] || fail "a ~name --hooks-json path printed an error: $err"
[[ -f "$tl/cwd/~nouser/hooks.json" ]] || fail "the ~name --hooks-json path was not taken as relative to the current directory"

# --remove puts back empty hooks keys the user had before KIS.
for original in '{"model":"m","hooks":{}}' '{"model":"m","hooks":{"SessionStart":[]}}'; do
  keep="$tmp_dir/keep-hooks"; rm -rf "$keep"; mkdir -p "$keep/.commandcode"
  printf '%s\n' "$original" > "$keep/.commandcode/settings.json"; printf '%s\n' "$original" > "$tmp_dir/keep-original.json"
  "$script_under_test" --target "$keep" --no-instructions >/dev/null
  "$script_under_test" --target "$keep" --remove --no-instructions >/dev/null
  same_json "$keep/.commandcode/settings.json" "$tmp_dir/keep-original.json" || fail "--remove changed $original into $(cat "$keep/.commandcode/settings.json")"
done

# --remove keeps a hook file the user had before KIS, even when removing the KIS entry empties it.
for original in '{}' '{"hooks":{}}'; do
  ue="$tmp_dir/user-empty"; rm -rf "$ue"; mkdir -p "$ue/.claude" "$ue/.codex" "$ue/.agents" "$ue/.commandcode"
  for f in .claude/settings.json .codex/hooks.json .agents/hooks.json .commandcode/settings.json; do printf '%s\n' "$original" > "$ue/$f"; done
  printf '%s\n' "$original" > "$tmp_dir/user-empty-original.json"
  "$script_under_test" --target "$ue" --no-instructions >/dev/null
  "$script_under_test" --target "$ue" --remove --no-instructions >/dev/null
  for f in .claude/settings.json .codex/hooks.json .agents/hooks.json .commandcode/settings.json; do
    [[ -f "$ue/$f" ]] || fail "--remove deleted $f, a file the user had ($original)"
    same_json "$ue/$f" "$tmp_dir/user-empty-original.json" || fail "--remove turned $f from $original into $(cat "$ue/$f")"
  done
done

# No locale (CI, a devcontainer): a hook file and an instruction file with an accented letter still work.
loc="$tmp_dir/locale"; rm -rf "$loc"; mkdir -p "$loc/.codex" "$loc/.claude" "$loc/.agents" "$loc/.commandcode"
printf '{"hooks":{},"note":"caf\xc3\xa9"}\n' > "$loc/.codex/hooks.json"; printf 'caf\xc3\xa9 notes\n' > "$loc/AGENTS.md"
printf '{"hooks":{},"note":"caf\xc3\xa9"}\n' > "$loc/.claude/settings.json"; printf '{"note":"caf\xc3\xa9"}\n' > "$loc/.agents/hooks.json"
printf '{"hooks":{},"note":"caf\xc3\xa9"}\n' > "$loc/.commandcode/settings.json"
rc=0; err="$(env -u LANG -u LC_ALL -u LC_CTYPE "$script_under_test" --target "$loc" 2>&1 >/dev/null)" || rc=$?
[[ "$rc" == 0 ]] || fail "install without a locale failed (exit $rc): $err"
accent="$(printf 'caf\xc3\xa9')"
for f in .codex/hooks.json .claude/settings.json .agents/hooks.json .commandcode/settings.json; do
  grep -q "$accent" "$loc/$f" || fail "install without a locale lost the non-ASCII text in $f"
  grep -q 'kis' "$loc/$f" || fail "install without a locale did not register the KIS entry in $f"
done
grep -q "$accent notes" "$loc/AGENTS.md" && grep -q 'kis:anchor:start' "$loc/AGENTS.md" || fail "install without a locale lost non-ASCII text or the KIS block"
rc=0; env -u LANG -u LC_ALL -u LC_CTYPE "$script_under_test" --target "$loc" --remove >/dev/null 2>&1 || rc=$?
[[ "$rc" == 0 ]] && grep -q "$accent notes" "$loc/AGENTS.md" || fail "--remove without a locale failed (exit $rc) or lost text"

# Files the hosts would reject (comments, trailing commas) abort the run before anything is written.
strict="$tmp_dir/strict"
for bad in $'// c\n{"hooks":{}}' $'{"hooks":{} /* c */}' '{"hooks":{},}'; do
  rm -rf "$strict"; mkdir -p "$strict/.codex"; printf '%s\n' "$bad" > "$strict/.codex/hooks.json"
  rc=0; err="$("$script_under_test" --target "$strict" 2>&1 >/dev/null)" || rc=$?
  [[ "$rc" != 0 && "$err" == *"cannot parse"*"hooks.json"* ]] || fail "install accepted $bad (exit $rc): $err"
  [[ ! -e "$strict/.claude" && ! -e "$strict/.agents" && ! -e "$strict/.commandcode" && ! -e "$strict/AGENTS.md" ]] || fail "install wrote files before aborting on $bad"
  [[ "$(cat "$strict/.codex/hooks.json")" == "$bad" ]] || fail "install changed the rejected file $bad"
done
rm -rf "$strict"; mkdir -p "$strict/.codex"; printf '{"permissions":{"allow":["Bash(ls /*)","Read(//tmp/**)"]},"hooks":{}}\n' > "$strict/.codex/hooks.json"
"$script_under_test" --target "$strict" --no-instructions >/dev/null || fail "install rejected a valid file whose strings contain // and /*"
grep -q 'Bash(ls /\*)' "$strict/.codex/hooks.json" || fail "install dropped a string containing /*"

echo "install-anchor tests: pass"
