#!/usr/bin/env bash
set -euo pipefail

script_under_test="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/kis/scripts" && pwd)/install-commands.sh}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

target_root="$tmp_dir/project"
skill_dir="$target_root/.agents/skills/kis"
codex_dir="$tmp_dir/codex-prompts"

mkdir -p "$skill_dir/commands"
printf -- '---\ndescription: test\n---\n\n# Start\n' > "$skill_dir/commands/start.md"
printf -- '---\ndescription: test\n---\n\n# Sync\n' > "$skill_dir/commands/sync.md"

fail() {
  echo "$*" >&2
  exit 1
}

"$script_under_test" --target "$target_root" >/dev/null

link="$target_root/.claude/commands/kis"
[[ -L "$link" ]] || fail "Claude command link was not created"
[[ "$(readlink "$link")" == "../../.agents/skills/kis/commands" ]] || fail "Claude command link is not relative to the project"
[[ -f "$link/start.md" ]] || fail "Claude command link is broken"

"$script_under_test" --target "$target_root" >/dev/null
[[ -f "$link/start.md" ]] || fail "re-running install broke the Claude command link"

pi_link="$target_root/.pi/prompts/kis-start.md"
[[ -L "$pi_link" ]] || fail "Pi prompt link was not created by the default host"
[[ "$(readlink "$pi_link")" == "../../.agents/skills/kis/commands/start.md" ]] || fail "Pi prompt link is not relative to the project"
[[ -f "$pi_link" ]] || fail "Pi prompt link is broken"
[[ -L "$target_root/.pi/prompts/kis-sync.md" ]] || fail "Pi prompt link was not created for every command"

codex_output="$("$script_under_test" --target "$target_root" --host codex --codex-prompts-dir "$codex_dir")"
[[ -f "$codex_dir/kis-start.md" ]] || fail "Codex prompt was not installed"
[[ -f "$codex_dir/kis-sync.md" ]] || fail "Codex prompt was not installed"
[[ "$codex_output" == *"2 file(s)"* ]] || fail "Codex install did not report installed count"

"$script_under_test" --target "$target_root" --host all --codex-prompts-dir "$codex_dir" --remove >/dev/null
[[ ! -e "$link" ]] || fail "--remove left the Claude command link"
[[ ! -e "$pi_link" && ! -L "$pi_link" ]] || fail "--remove left Pi prompt links"
[[ ! -f "$codex_dir/kis-start.md" ]] || fail "--remove left Codex prompts"

empty_skill="$tmp_dir/empty/.agents/skills/kis"
mkdir -p "$empty_skill"
empty_output="$("$script_under_test" --target "$tmp_dir/empty")"
[[ "$empty_output" == *"skipped"* ]] || fail "missing commands/ should be skipped, not fatal"

set +e
"$script_under_test" --target "$target_root" --host bogus >/dev/null 2>&1
bad_host_status=$?
set -e
[[ "$bad_host_status" -ne 0 ]] || fail "unknown host should fail"

echo "install-commands tests: pass"
