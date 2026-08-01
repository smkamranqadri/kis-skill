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
  --commands-host <n>   Command adapters: project (default: claude and pi), claude, pi,
                        codex, or all. Only codex writes outside the project.
  --no-commands         Do not install or refresh command adapters.
  --no-anchor           Do not install or refresh the re-anchor hook and instruction block.
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
install_commands="true"
commands_host="project"
install_anchor="true"

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

refresh_adapters() {
  if [[ "$install_commands" == "true" && -x "$install_dir/scripts/install-commands.sh" ]]; then
    "$install_dir/scripts/install-commands.sh" \
      --target "$target_root" \
      --skill-dir "$install_dir" \
      --host "$commands_host"
  fi

  if [[ "$install_anchor" == "true" && -x "$install_dir/scripts/install-anchor.sh" ]]; then
    "$install_dir/scripts/install-anchor.sh" --target "$target_root"
  fi
}

case "$command_name" in
  install)
    args=(--source "$source_arg" --target "$target_root" --commands-host "$commands_host")
    [[ "$force" == "true" ]] && args+=(--force)
    [[ "$create_claude_link" == "false" ]] && args+=(--no-claude-link)
    [[ "$install_commands" == "false" ]] && args+=(--no-commands)
    [[ "$install_anchor" == "false" ]] && args+=(--no-anchor)
    "$source_arg/scripts/install-skill.sh" "${args[@]}"
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
    refresh_adapters
    ;;
esac
