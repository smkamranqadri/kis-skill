#!/usr/bin/env bash
set -euo pipefail

script_under_test="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/kis/scripts" && pwd)/install-commands.sh}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
# The installers write Codex prompts under CODEX_HOME when it exists; point it at nothing so a test never touches the real one.
export CODEX_HOME="$tmp_dir/no-codex"

target_root="$tmp_dir/project"
skill_dir="$target_root/.agents/skills/kis"
codex_dir="$tmp_dir/codex-prompts"

mkdir -p "$skill_dir/commands"
printf -- '---\ndescription: test\n---\n\n# Start\n' > "$skill_dir/commands/start.md"
printf -- '---\ndescription: test\n---\n\n# Sync\n' > "$skill_dir/commands/sync.md"
printf -- '---\ndescription: test\n---\n\n# Gadget\n' > "$skill_dir/commands/gadget.md"

fail() {
  echo "$*" >&2
  exit 1
}

"$script_under_test" --target "$target_root" >/dev/null

link="$target_root/.claude/commands/kis"
[[ -L "$link" ]] || fail "Claude command link was not created"
[[ "$(readlink "$link")" == "../../.agents/skills/kis/commands" ]] || fail "Claude command link is not relative to the project"
[[ -f "$link/start.md" ]] || fail "Claude command link is broken"
[[ -f "$link/gadget.md" ]] || fail "Claude command link does not reach gadget"

"$script_under_test" --target "$target_root" >/dev/null
[[ -f "$link/start.md" ]] || fail "re-running install broke the Claude command link"

pi_link="$target_root/.pi/prompts/kis-start.md"
[[ -L "$pi_link" ]] || fail "Pi prompt link was not created by the default host"
[[ "$(readlink "$pi_link")" == "../../.agents/skills/kis/commands/start.md" ]] || fail "Pi prompt link is not relative to the project"
[[ -f "$pi_link" ]] || fail "Pi prompt link is broken"
[[ -L "$target_root/.pi/prompts/kis-sync.md" ]] || fail "Pi prompt link was not created for every command"
[[ -f "$target_root/.pi/prompts/kis-gadget.md" ]] || fail "Pi prompt link was not created for gadget"

opencode_link="$target_root/.opencode/command/kis-start.md"
[[ ! -e "$opencode_link" ]] || fail "the default host should not install OpenCode commands"

"$script_under_test" --target "$target_root" --host opencode >/dev/null
[[ -L "$opencode_link" ]] || fail "OpenCode command link was not created"
[[ "$(readlink "$opencode_link")" == "../../.agents/skills/kis/commands/start.md" ]] || fail "OpenCode command link is not relative to the project"
[[ -f "$opencode_link" ]] || fail "OpenCode command link is broken"
[[ -L "$target_root/.opencode/command/kis-sync.md" ]] || fail "OpenCode command link was not created for every command"
[[ -f "$target_root/.opencode/command/kis-gadget.md" ]] || fail "OpenCode command link was not created for gadget"

codex_output="$("$script_under_test" --target "$target_root" --host codex --codex-prompts-dir "$codex_dir")"
[[ -f "$codex_dir/kis-start.md" ]] || fail "Codex prompt was not installed"
[[ -f "$codex_dir/kis-sync.md" ]] || fail "Codex prompt was not installed"
[[ -f "$codex_dir/kis-gadget.md" ]] || fail "Codex prompt was not installed for gadget"
[[ "$codex_output" == *"3 file(s)"* ]] || fail "Codex install did not report installed count"

"$script_under_test" --target "$target_root" --host all --codex-prompts-dir "$codex_dir" --remove >/dev/null
[[ ! -e "$link" ]] || fail "--remove left the Claude command link"
[[ ! -e "$pi_link" && ! -L "$pi_link" ]] || fail "--remove left Pi prompt links"
[[ ! -e "$opencode_link" && ! -L "$opencode_link" ]] || fail "--remove left OpenCode command links"
[[ ! -f "$codex_dir/kis-start.md" ]] || fail "--remove left Codex prompts"

# auto (the default) adds Codex only where the Codex home directory exists; project never does.
auto_home="$tmp_dir/auto-codex-home"
mkdir -p "$auto_home"
auto_output="$(CODEX_HOME="$auto_home" "$script_under_test" --target "$target_root")"
[[ -f "$auto_home/prompts/kis-start.md" && -f "$auto_home/prompts/kis-gadget.md" ]] || fail "auto did not install Codex prompts into an existing Codex home"
[[ "$auto_output" == *"Codex prompts: 3 file(s)"* ]] || fail "auto did not report the Codex install: $auto_output"
CODEX_HOME="$auto_home" "$script_under_test" --target "$target_root" --remove >/dev/null
[[ ! -e "$auto_home/prompts/kis-start.md" && ! -e "$auto_home/prompts/kis-gadget.md" ]] || fail "auto --remove left Codex prompts"
[[ ! -e "$link" ]] || fail "auto --remove left the Claude command link"

CODEX_HOME="$auto_home" "$script_under_test" --target "$target_root" --host project >/dev/null
[[ -z "$(find "$auto_home" -name 'kis-*.md' 2>/dev/null)" ]] || fail "--host project wrote Codex prompts"

missing_home="$tmp_dir/no-such-codex-home"
missing_output="$(CODEX_HOME="$missing_home" "$script_under_test" --target "$target_root")"
[[ ! -e "$missing_home" ]] || fail "auto created a Codex home that did not exist"
[[ "$missing_output" == *"Codex prompts: skipped ($missing_home not found; use --host codex to install anyway)"* ]] || fail "auto did not say why Codex was skipped: $missing_output"
[[ -L "$target_root/.pi/prompts/kis-start.md" ]] || fail "auto skipped the project hosts when Codex was missing"

CODEX_HOME="$missing_home" "$script_under_test" --target "$target_root" --host codex >/dev/null
[[ -f "$missing_home/prompts/kis-start.md" ]] || fail "--host codex did not install into a missing Codex home"

# A command dropped from the package loses its adapter on every host at the next install; other
# commands and files that are not KIS adapters stay.
"$script_under_test" --target "$target_root" --host all --codex-prompts-dir "$codex_dir" >/dev/null
printf 'mine\n' > "$codex_dir/my-prompt.md"
printf 'mine\n' > "$target_root/.pi/prompts/my-prompt.md"
rm "$skill_dir/commands/gadget.md"
"$script_under_test" --target "$target_root" --host all --codex-prompts-dir "$codex_dir" >/dev/null
for dropped in "$target_root/.pi/prompts/kis-gadget.md" "$target_root/.opencode/command/kis-gadget.md" "$codex_dir/kis-gadget.md"; do
  [[ ! -e "$dropped" && ! -L "$dropped" ]] || fail "a dropped command kept its adapter: $dropped"
done
[[ "$(find "$target_root/.pi/prompts" "$target_root/.opencode/command" "$codex_dir" -name 'kis-*.md' | wc -l | tr -d ' ')" == "6" ]] || fail "pruning removed adapters of shipped commands"
[[ -f "$codex_dir/my-prompt.md" && -f "$target_root/.pi/prompts/my-prompt.md" ]] || fail "pruning removed a file that is not a KIS adapter"

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
