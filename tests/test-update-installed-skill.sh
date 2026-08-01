#!/usr/bin/env bash
set -euo pipefail

script_under_test="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/kis/scripts" && pwd)/update-installed-skill.sh}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

source_dir="$tmp_dir/source/kis"
install_dir="$tmp_dir/project/.agents/skills/kis"

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

write_skill "$source_dir" "0.6.1" "new-package"
write_skill "$install_dir" "0.6.0" "old-package"

check_output="$("$script_under_test" --source "$source_dir" --install-dir "$install_dir" --check)"
assert_contains "$check_output" "Update available: 0.6.0 -> 0.6.1"

if [[ "$(read_version "$install_dir")" != "0.6.0" ]]; then
  echo "Check mode mutated installed version" >&2
  exit 1
fi

apply_output="$("$script_under_test" --source "$source_dir" --install-dir "$install_dir" --apply)"
assert_contains "$apply_output" "Updated KIS skill: 0.6.0 -> 0.6.1"

if [[ "$(read_version "$install_dir")" != "0.6.1" ]]; then
  echo "Apply mode did not update installed version" >&2
  exit 1
fi

if [[ "$(cat "$install_dir/MARKER.txt")" != "new-package" ]]; then
  echo "Apply mode did not copy source package contents" >&2
  exit 1
fi

current_output="$("$script_under_test" --source "$source_dir" --install-dir "$install_dir" --check)"
assert_contains "$current_output" "Already current: 0.6.1"

echo "update-installed-skill tests: pass"
