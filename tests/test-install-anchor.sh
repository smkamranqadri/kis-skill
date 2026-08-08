#!/usr/bin/env bash
set -euo pipefail

script_under_test="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/kis/scripts" && pwd)/install-anchor.sh}"
package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/kis" && pwd)"
hook_script="$package_dir/hooks/session-anchor.sh"
antigravity_hook_script="$package_dir/hooks/antigravity-anchor.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

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

"$script_under_test" --target "$target_root" >/dev/null

[[ "$(count_kis_hooks)" == "1" ]] || fail "anchor hook was not registered exactly once"
grep -q '"Bash(git status:\*)"' "$settings" || fail "existing settings content was lost"
grep -q 'echo existing' "$settings" || fail "existing hook was lost"
grep -q 'Existing instructions.' "$agents_file" || fail "existing instructions were lost"
grep -q '<!-- kis:anchor:start -->' "$agents_file" || fail "KIS block was not added"
grep -q '/kis:start' "$agents_file" || fail "KIS block is missing the command list"
grep -q '"kis-anchor"' "$hooks_json" || fail "Antigravity hook was not registered"
grep -q './skills/kis/hooks/antigravity-anchor.sh' "$hooks_json" || fail "Antigravity hook command is not relative to .agents/"
grep -q '"PreInvocation"' "$hooks_json" || fail "Antigravity hook is not on PreInvocation"
grep -q 'echo guard' "$hooks_json" || fail "an unrelated Antigravity hook was lost"

"$script_under_test" --target "$target_root" >/dev/null
[[ "$(count_kis_hooks)" == "1" ]] || fail "re-running duplicated the anchor hook"
[[ "$(grep -c '<!-- kis:anchor:start -->' "$agents_file")" == "1" ]] || fail "re-running duplicated the KIS block"

check_output="$("$script_under_test" --target "$target_root" --check)"
[[ "$check_output" == *"installed"* ]] || fail "--check did not report the hook"
[[ "$check_output" == *"Antigravity PreInvocation hook: installed"* ]] || fail "--check did not report the Antigravity hook"
[[ "$check_output" == *"KIS block present"* ]] || fail "--check did not report the block"

"$script_under_test" --target "$target_root" --remove >/dev/null
[[ "$(count_kis_hooks)" == "0" ]] || fail "--remove left the anchor hook"
grep -q 'kis-anchor' "$hooks_json" && fail "--remove left the Antigravity hook"
grep -q 'echo guard' "$hooks_json" || fail "--remove deleted an unrelated Antigravity hook"
grep -q 'echo existing' "$settings" || fail "--remove deleted an unrelated hook"
grep -q '<!-- kis:anchor:start -->' "$agents_file" && fail "--remove left the KIS block"
grep -q 'Existing instructions.' "$agents_file" || fail "--remove deleted unrelated instructions"

fresh_root="$tmp_dir/fresh"
"$script_under_test" --target "$fresh_root" >/dev/null
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

marker_home="$tmp_dir/hook-markers"
mkdir -p "$marker_home"
antigravity_payload="{\"conversationId\":\"conv-1\",\"workspacePaths\":[\"$kis_root\"]}"
antigravity_output="$(printf '%s' "$antigravity_payload" | TMPDIR="$marker_home" "$antigravity_hook_script")"
[[ "$antigravity_output" == *'"injectSteps"'* ]] || fail "Antigravity hook did not inject a step"
[[ "$antigravity_output" == *"Task: wire commands"* ]] || fail "Antigravity hook did not inject State"

repeat_output="$(printf '%s' "$antigravity_payload" | TMPDIR="$marker_home" "$antigravity_hook_script")"
[[ "$repeat_output" == "{}" ]] || fail "Antigravity hook injected twice in one conversation"

second_output="$(printf '{"conversationId":"conv-2","workspacePaths":["%s"]}' "$kis_root" | TMPDIR="$marker_home" "$antigravity_hook_script")"
[[ "$second_output" == *'"injectSteps"'* ]] || fail "Antigravity hook did not inject for a new conversation"

garbage_output="$(printf 'not json' | TMPDIR="$marker_home" "$antigravity_hook_script")"
[[ "$garbage_output" == *'"injectSteps"'* || "$garbage_output" == "{}" ]] || fail "Antigravity hook did not emit JSON for an unparsable payload"

echo "install-anchor tests: pass"
