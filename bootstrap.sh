#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bootstrap.sh [install|check|update] [options]

Commands:
  install  Install KIS into a project. Default command.
  check    Check whether an installed KIS skill has an update.
  update   Apply an update to an installed KIS skill.

Options:
  --repo <git-url>      Git repository to clone as the source.
                        Can also be set with KIS_SKILL_REPO.
  --ref <git-ref>       Git ref to install from. Defaults to main.
                        Can also be set with KIS_SKILL_REF.
  --source <path>       Local source repo/package path. Skips git clone.
  --target <path>       Project root for install. Defaults to current directory.
  --install-dir <path>  Installed skill package for check/update.
                        Defaults to <target>/.agents/skills/kis.
  --force               Replace an existing install during install.
  --no-claude-link      Do not create .claude/skills/kis compatibility symlink.
  -h, --help            Show this help.

Examples:
  bootstrap.sh install --repo https://github.com/OWNER/kis-loop-skill.git
  bootstrap.sh check --repo https://github.com/OWNER/kis-loop-skill.git
  bootstrap.sh update --repo https://github.com/OWNER/kis-loop-skill.git
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

command_name="install"
if [[ $# -gt 0 ]]; then
  case "$1" in
    install|check|update)
      command_name="$1"
      shift
      ;;
  esac
fi

repo_url="${KIS_SKILL_REPO:-}"
repo_ref="${KIS_SKILL_REF:-main}"
source_arg=""
target_root="."
install_dir=""
force="false"
create_claude_link="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || die "--repo requires a git URL"
      repo_url="$2"
      shift 2
      ;;
    --ref)
      [[ $# -ge 2 ]] || die "--ref requires a git ref"
      repo_ref="$2"
      shift 2
      ;;
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
    --install-dir)
      [[ $# -ge 2 ]] || die "--install-dir requires a path"
      install_dir="$2"
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
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [[ -z "$source_arg" ]]; then
  [[ -n "$repo_url" ]] || die "missing --repo <git-url>, KIS_SKILL_REPO, or --source <path>"
  command -v git >/dev/null 2>&1 || die "git is required when using --repo"

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  git clone --depth 1 --branch "$repo_ref" "$repo_url" "$tmp_dir/kis-loop-skill" >/dev/null
  source_arg="$tmp_dir/kis-loop-skill"
fi

target_root="$(mkdir -p "$target_root" && cd "$target_root" && pwd -P)"
if [[ -z "$install_dir" ]]; then
  install_dir="$target_root/.agents/skills/kis"
fi

case "$command_name" in
  install)
    args=(--source "$source_arg" --target "$target_root")
    [[ "$force" == "true" ]] && args+=(--force)
    [[ "$create_claude_link" == "false" ]] && args+=(--no-claude-link)
    "$source_arg/.agents/skills/kis/scripts/install-skill.sh" "${args[@]}"
    ;;
  check)
    "$install_dir/scripts/update-installed-skill.sh" \
      --source "$source_arg" \
      --install-dir "$install_dir" \
      --check
    ;;
  update)
    "$install_dir/scripts/update-installed-skill.sh" \
      --source "$source_arg" \
      --install-dir "$install_dir" \
      --apply
    ;;
esac
