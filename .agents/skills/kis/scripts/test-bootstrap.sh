#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd -P)"
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

target_no_link="$tmp_dir/no-link-project"
mkdir -p "$target_no_link"
"$bootstrap_script" install --source "$repo_root" --target "$target_no_link" --no-claude-link >/tmp/kis-bootstrap-no-link.out
grep -q "Claude compatibility link: skipped" /tmp/kis-bootstrap-no-link.out
test ! -e "$target_no_link/.claude/skills/kis"

echo "bootstrap tests: pass"
