#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  install-skill.sh --source <skill-dir-or-repo-root> [--target <project-root>] [--force] [--no-claude-link]
                   [--commands-host project|claude|pi|codex|all]
                   [--no-commands] [--no-anchor]

Options:
  --source <path>            Source skill package or repo root containing .agents/skills/kis.
                             Can also be set with KIS_SKILL_SOURCE.
  --target <path>            Project root to install into. Defaults to current directory.
  --force                    Replace an existing .agents/skills/kis install.
  --no-claude-link           Do not create .claude/skills/kis compatibility symlink.
  --commands-host <name>     Command adapters: project (default: claude and pi), claude, pi,
                             codex, or all. Only codex writes outside the project.
  --no-commands              Do not install command adapters.
  --no-anchor                Do not install the re-anchor hook and instruction block.
  -h, --help                 Show this help.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

source_arg="${KIS_SKILL_SOURCE:-}"
target_root="."
force="false"
create_claude_link="true"
install_commands="true"
commands_host="project"
install_anchor="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || die "--source requires a path"
      source_arg="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || die "--target requires a path"
      target_root="$2"
      shift 2
      ;;
    --force)
      force="true"
      shift
      ;;
    --no-claude-link)
      create_claude_link="false"
      shift
      ;;
    --commands-host)
      [[ $# -ge 2 ]] || die "--commands-host requires project, claude, pi, codex, or all"
      commands_host="$2"
      shift 2
      ;;
    --no-commands)
      install_commands="false"
      shift
      ;;
    --no-anchor)
      install_anchor="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$source_arg" ]] || die "missing --source <skill-dir-or-repo-root> or KIS_SKILL_SOURCE"

normalize_skill_dir() {
  local candidate="$1"

  if [[ -f "$candidate/SKILL.md" ]]; then
    (cd "$candidate" && pwd -P)
    return 0
  fi

  # source repo layout
  if [[ -f "$candidate/skills/kis/SKILL.md" ]]; then
    (cd "$candidate/skills/kis" && pwd -P)
    return 0
  fi

  # installed project layout
  if [[ -f "$candidate/.agents/skills/kis/SKILL.md" ]]; then
    (cd "$candidate/.agents/skills/kis" && pwd -P)
    return 0
  fi

  return 1
}

read_skill_version() {
  local skill_dir="$1"

  ruby -ryaml -e '
    path = File.join(ARGV.fetch(0), "SKILL.md")
    text = File.read(path)
    frontmatter = text[/\A---\n(.*?)\n---\n/m, 1]
    abort("missing YAML frontmatter in #{path}") unless frontmatter
    data = YAML.safe_load(frontmatter)
    version = data.dig("metadata", "version")
    abort("missing metadata.version in #{path}") if version.to_s.strip.empty?
    puts version
  ' "$skill_dir"
}

validate_skill_dir() {
  local skill_dir="$1"

  if [[ -x "$skill_dir/scripts/validate-skill.sh" ]]; then
    "$skill_dir/scripts/validate-skill.sh" "$skill_dir" >/dev/null
    return 0
  fi

  [[ -f "$skill_dir/SKILL.md" ]] || die "source package missing SKILL.md: $skill_dir"
}

source_dir="$(normalize_skill_dir "$source_arg")" || die "source is not a KIS skill package or repo root: $source_arg"
target_root="$(mkdir -p "$target_root" && cd "$target_root" && pwd -P)"
install_dir="$target_root/.agents/skills/kis"
claude_link="$target_root/.claude/skills/kis"
source_version="$(read_skill_version "$source_dir")"

validate_skill_dir "$source_dir"

if [[ -e "$install_dir" || -L "$install_dir" ]]; then
  if [[ "$force" != "true" ]]; then
    die "install already exists at $install_dir; use --force to replace it or update-installed-skill.sh to update it"
  fi
  rm -rf "$install_dir"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/kis"
cp -R "$source_dir/." "$tmp_dir/kis/"
validate_skill_dir "$tmp_dir/kis"

mkdir -p "$(dirname "$install_dir")"
cp -R "$tmp_dir/kis" "$install_dir"
validate_skill_dir "$install_dir"

if [[ "$create_claude_link" == "true" ]]; then
  mkdir -p "$(dirname "$claude_link")"
  rm -rf "$claude_link"
  ln -s "../../.agents/skills/kis" "$claude_link"
fi

echo "Installed KIS skill: $source_version"
echo "Install: $install_dir"
if [[ "$create_claude_link" == "true" ]]; then
  echo "Claude compatibility link: $claude_link"
else
  echo "Claude compatibility link: skipped"
fi

if [[ "$install_commands" == "true" && -x "$install_dir/scripts/install-commands.sh" ]]; then
  "$install_dir/scripts/install-commands.sh" \
    --target "$target_root" \
    --skill-dir "$install_dir" \
    --host "$commands_host"
else
  echo "Command adapters: skipped"
fi

if [[ "$install_anchor" == "true" && -x "$install_dir/scripts/install-anchor.sh" ]]; then
  "$install_dir/scripts/install-anchor.sh" --target "$target_root"
else
  echo "Re-anchor layer: skipped"
fi
