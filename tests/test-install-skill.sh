#!/usr/bin/env bash
set -euo pipefail

script_under_test="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/install-skill.sh}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
# The installers write Codex prompts under CODEX_HOME when it exists; point it at nothing so a test never touches the real one.
export CODEX_HOME="$tmp_dir/no-codex"

source_root="$tmp_dir/source-repo"
source_dir="$source_root/skills/kis"
target_root="$tmp_dir/target-project"

write_skill() {
  local dir="$1"
  local version="$2"
  local marker="$3"

  mkdir -p "$dir/scripts" "$dir/references"
  printf '%s\n' "$marker" > "$dir/MARKER.txt"
  cat > "$dir/SKILL.md" <<EOF
---
name: kis
description: Test KIS skill package.
metadata:
  version: "$version"
---

# Test Skill
EOF
  cat > "$dir/scripts/validate-skill.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
skill_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
test -f "$skill_dir/SKILL.md"
EOF
  chmod +x "$dir/scripts/validate-skill.sh"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Expected output to contain: $needle" >&2
    echo "Actual output:" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

read_version() {
  ruby -ryaml -e '
    text = File.read(ARGV.fetch(0))
    frontmatter = text[/\A---\n(.*?)\n---\n/m, 1]
    puts YAML.safe_load(frontmatter).dig("metadata", "version")
  ' "$1/SKILL.md"
}

write_skill "$source_dir" "0.7.0" "first-install"
mkdir -p "$target_root"

install_output="$("$script_under_test" --source "$source_root" --target "$target_root")"
assert_contains "$install_output" "Installed KIS skill: 0.7.0"

installed_dir="$target_root/.agents/skills/kis"
if [[ "$(read_version "$installed_dir")" != "0.7.0" ]]; then
  echo "Install did not copy expected version" >&2
  exit 1
fi

if [[ "$(cat "$installed_dir/MARKER.txt")" != "first-install" ]]; then
  echo "Install did not copy source package contents" >&2
  exit 1
fi

if [[ ! -L "$target_root/.claude/skills/kis" ]]; then
  echo "Install did not create Claude compatibility symlink" >&2
  exit 1
fi

if [[ ! -f "$target_root/.claude/skills/kis/SKILL.md" ]]; then
  echo "Claude compatibility symlink is broken" >&2
  exit 1
fi

set +e
refuse_output="$("$script_under_test" --source "$source_root" --target "$target_root" 2>&1)"
refuse_status=$?
set -e

if [[ "$refuse_status" -eq 0 ]]; then
  echo "Install should refuse existing install without --force" >&2
  exit 1
fi
assert_contains "$refuse_output" "already exists"

write_skill "$source_dir" "0.7.1" "forced-install"
force_output="$("$script_under_test" --source "$source_root" --target "$target_root" --force)"
assert_contains "$force_output" "Installed KIS skill: 0.7.1"

if [[ "$(read_version "$installed_dir")" != "0.7.1" ]]; then
  echo "Force install did not replace expected version" >&2
  exit 1
fi

if [[ "$(cat "$installed_dir/MARKER.txt")" != "forced-install" ]]; then
  echo "Force install did not replace package contents" >&2
  exit 1
fi

target_no_link="$tmp_dir/no-link-project"
mkdir -p "$target_no_link"
no_link_output="$("$script_under_test" --source "$source_root" --target "$target_no_link" --no-claude-link)"
assert_contains "$no_link_output" "Installed KIS skill: 0.7.1"

if [[ -e "$target_no_link/.claude/skills/kis" ]]; then
  echo "--no-claude-link created a Claude compatibility link" >&2
  exit 1
fi

echo "install-skill tests: pass"
