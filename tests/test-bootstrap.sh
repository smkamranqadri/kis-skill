#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
bootstrap_script="$repo_root/bootstrap.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

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

echo "bootstrap tests: pass"
