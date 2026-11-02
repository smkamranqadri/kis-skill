#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
bootstrap_script="$repo_root/bootstrap.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
# The installers write Codex prompts under CODEX_HOME when it exists; point it at nothing so a test never touches the real one.
export CODEX_HOME="$tmp_dir/no-codex"

target="$tmp_dir/project"
mkdir -p "$target"

"$bootstrap_script" install --source "$repo_root" --target "$target" >/tmp/kis-bootstrap-install.out
grep -q "Installed KIS skill:" /tmp/kis-bootstrap-install.out
test -f "$target/.agents/skills/kis/SKILL.md"
test -L "$target/.claude/skills/kis"
test -f "$target/.claude/skills/kis/SKILL.md"

"$bootstrap_script" check --source "$repo_root" --target "$target" >/tmp/kis-bootstrap-check.out
grep -q "Already current:" /tmp/kis-bootstrap-check.out

"$bootstrap_script" update --source "$repo_root" --target "$target" >/tmp/kis-bootstrap-update.out
grep -q "Already current:" /tmp/kis-bootstrap-update.out

legacy="$tmp_dir/legacy-project"
legacy_install="$legacy/.agents/skills/kis/scripts"
mkdir -p "$legacy_install"
printf -- '---\nname: kis\ndescription: legacy\nmetadata:\n  version: "0.0.1"\n---\n\n# KIS\n' \
  > "$legacy/.agents/skills/kis/SKILL.md"
cat > "$legacy_install/update-installed-skill.sh" <<'EOF'
#!/usr/bin/env bash
echo "Error: source is not a KIS skill package or repo root" >&2
exit 1
EOF
chmod +x "$legacy_install/update-installed-skill.sh"

"$bootstrap_script" update --source "$repo_root" --target "$legacy" >/tmp/kis-bootstrap-legacy.out 2>&1
grep -q "Reinstalling instead." /tmp/kis-bootstrap-legacy.out
grep -q "Installed KIS skill:" /tmp/kis-bootstrap-legacy.out
grep -q "$(cat "$repo_root/ACTIVE_VERSION")" "$legacy/.agents/skills/kis/SKILL.md"
test -d "$legacy/.agents/skills/kis/commands"
test -L "$legacy/.claude/commands/kis"
test -f "$legacy/.claude/commands/kis/start.md"

legacy_bare="$tmp_dir/legacy-bare-project"
mkdir -p "$legacy_bare/.agents/skills/kis"
printf -- '---\nname: kis\ndescription: legacy\n---\n\n# KIS\n' > "$legacy_bare/.agents/skills/kis/SKILL.md"
"$bootstrap_script" update --source "$repo_root" --target "$legacy_bare" >/tmp/kis-bootstrap-legacy-bare.out 2>&1
grep -q "No updater in" /tmp/kis-bootstrap-legacy-bare.out
test -f "$legacy_bare/.claude/commands/kis/start.md"

target_no_link="$tmp_dir/no-link-project"
mkdir -p "$target_no_link"
"$bootstrap_script" install --source "$repo_root" --target "$target_no_link" --no-claude-link >/tmp/kis-bootstrap-no-link.out
grep -q "Claude compatibility link: skipped" /tmp/kis-bootstrap-no-link.out
test ! -e "$target_no_link/.claude/skills/kis"

# Codex: the default host adds Codex prompts when the Codex home exists, and an update refreshes them.
codex_home="$tmp_dir/codex-home"
mkdir -p "$codex_home"
target_codex="$tmp_dir/codex-project"
mkdir -p "$target_codex"
CODEX_HOME="$codex_home" "$bootstrap_script" install --source "$repo_root" --target "$target_codex" >/dev/null
for command_file in "$repo_root"/skills/kis/commands/*.md; do
  cmp -s "$command_file" "$codex_home/prompts/kis-$(basename "$command_file")" || { echo "default install did not copy $(basename "$command_file") to the Codex prompts" >&2; exit 1; }
done
printf 'stale\n' > "$codex_home/prompts/kis-start.md"
rm -f "$codex_home/prompts/kis-compass.md"
sed -i 's/^  version: ".*"$/  version: "0.0.1"/' "$target_codex/.agents/skills/kis/SKILL.md"
CODEX_HOME="$codex_home" "$bootstrap_script" update --source "$repo_root" --target "$target_codex" >/dev/null
cmp -s "$repo_root/skills/kis/commands/start.md" "$codex_home/prompts/kis-start.md" || { echo "update did not refresh a stale Codex prompt" >&2; exit 1; }
cmp -s "$repo_root/skills/kis/commands/compass.md" "$codex_home/prompts/kis-compass.md" || { echo "update did not restore a missing Codex prompt" >&2; exit 1; }

target_project_only="$tmp_dir/project-only"
mkdir -p "$target_project_only" "$tmp_dir/untouched-codex-home"
CODEX_HOME="$tmp_dir/untouched-codex-home" "$bootstrap_script" install --source "$repo_root" --target "$target_project_only" --commands-host project >/dev/null
test ! -e "$tmp_dir/untouched-codex-home/prompts" || { echo "--commands-host project wrote Codex prompts" >&2; exit 1; }

# Every entry point defaults to the same host selection; the scripts that only forward it must not drift.
for entry in "$repo_root/bootstrap.sh" "$repo_root/scripts/install-skill.sh"; do
  grep -qx 'commands_host="auto"' "$entry" || { echo "$entry does not default --commands-host to auto" >&2; exit 1; }
done
grep -qx 'host="auto"' "$repo_root/skills/kis/scripts/install-commands.sh" || { echo "install-commands.sh does not default --host to auto" >&2; exit 1; }

echo "bootstrap tests: pass"
