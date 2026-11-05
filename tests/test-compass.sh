#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkg="${1:-$repo_root/skills/kis}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
# The installers write Codex prompts under CODEX_HOME when it exists; point it at nothing so a test never touches the real one.
export CODEX_HOME="$tmp_dir/no-codex"

fail() {
  echo "$*" >&2
  exit 1
}

has() { grep -qxF -- "$2" "$1"; }
contains() { grep -qF -- "$2" "$1"; }

skill_md="$pkg/SKILL.md"
init_md="$pkg/commands/init.md"
plan_md="$pkg/commands/plan.md"
bootstrap_md="$pkg/references/bootstrap.md"

# The compass is a file init writes, not a command: no command, no reference of its own.
[[ ! -e "$pkg/commands/compass.md" ]] || fail "commands/compass.md exists; the compass has no command"
[[ ! -e "$pkg/references/product-compass.md" ]] || fail "references/product-compass.md exists; bootstrap.md owns the compass shape"
grep -rqi 'compass command\|/kis:compass\|kis-compass' "$pkg" && fail "the package still mentions a compass command: $(grep -rli 'compass command\|/kis:compass\|kis-compass' "$pkg" | paste -sd ' ' -)"

# SKILL.md: one line per layer says which file holds today and which holds the direction.
has "$skill_md" '  knowledge/   stable facts: stack, architecture, domain terms, constraints, standards, durable decisions; project.md says what the product is today' || fail "SKILL.md Knowledge line does not name project.md as today"
has "$skill_md" '  intent/      direction: compass.md (where the product is going), PRDs, plans, acceptance criteria, design direction' || fail "SKILL.md Intent line does not name compass.md as the direction"
[[ "$(grep -c 'compass' "$skill_md")" == "1" ]] || fail "SKILL.md says more about the compass than its layer line"

# init asks the direction questions and writes both files; a project without a compass is incomplete.
contains "$init_md" 'then the direction: why it should exist, the vision, the North Star, principles, what not to build, and POC versus MVP.' || fail "init.md does not ask the direction questions"
contains "$init_md" 'A missing `kis/intent/compass.md` counts as incomplete.' || fail "init.md cannot add a compass to an existing project"
contains "$init_md" 'What the product is today goes to `kis/knowledge/project.md`; where it is going goes to `kis/intent/compass.md`' || fail "init.md does not split today from direction"
contains "$bootstrap_md" 'then the direction: why it should exist, the vision, the North Star, principles, what not to build, and POC versus MVP.' || fail "bootstrap.md does not ask the direction questions"
contains "$bootstrap_md" 'what the product is today in `knowledge/project.md`, where it is going in `intent/compass.md`' || fail "bootstrap.md does not write both files"

# bootstrap.md owns the compass shape and its two guards.
has "$bootstrap_md" '## Compass' || fail "bootstrap.md lost the Compass section"
compass_shape="$(awk '/^## Compass$/ {f = 1} f && /^```text$/ {g = 1; next} g && /^```$/ {exit} g {print}' "$bootstrap_md" | paste -sd '|' -)"
[[ "$compass_shape" == "# Compass: <product>||## Why|## Who and problem|## Vision|## North Star|## Principles|## Not building|## POC vs MVP|### POC (testing)|### MVP (committed)" ]] || fail "bootstrap.md compass shape changed: $compass_shape"
has "$bootstrap_md" '- Never invent metrics, targets, or a North Star. Without one the user can name, write `none yet`.' || fail "bootstrap.md lost the invented-metrics guard"
has "$bootstrap_md" '- Mark a belief that is not yet proven as a hypothesis.' || fail "bootstrap.md lost the hypothesis guard"
contains "$bootstrap_md" 'The vision stays stable while features, technology, and experiments change, so keep those out of the compass.' || fail "bootstrap.md lost the stable-vision rule"
has "$bootstrap_md" '    compass.md' || fail "bootstrap.md suggested files omit compass.md"
has "$bootstrap_md" 'Product direction   -> intent/compass.md' || fail "bootstrap.md document mapping omits the compass"

# plan reads both files.
contains "$plan_md" 'Read `kis/knowledge/project.md` and `kis/intent/compass.md` when they exist.' || fail "plan.md does not read project.md and compass.md"

# The command lists name no compass command.
project="$tmp_dir/project"
mkdir -p "$project/.agents/skills" "$project/kis/state"
cp -R "$pkg" "$project/.agents/skills/kis"
printf 'Branch: main\nTask: x\nNext: y\n' > "$project/kis/state/current.md"
[[ "$(grep -c '^Commands in .agents/skills/kis/commands/: start, plan, act, sync, check, init\.$' <<< "$("$pkg/hooks/session-anchor.sh" "$project")")" == "1" ]] || fail "session anchor command list is wrong"
"$pkg/scripts/install-anchor.sh" --target "$project" --no-hook >/dev/null
grep -qxF -- '- Commands live in `.agents/skills/kis/commands/`: start, plan, act, sync, check, init.' "$project/AGENTS.md" || fail "AGENTS.md KIS block command list is wrong"
install_out="$("$pkg/scripts/install-commands.sh" --target "$project" --host all --codex-prompts-dir "$tmp_dir/codex")"
[[ "$install_out" != *compass* ]] || fail "installer usage lines still name compass"

if [[ "$pkg" == "$repo_root/skills/kis" ]]; then
  # Versions agree (AGENTS.md: ACTIVE_VERSION and metadata.version must match).
  [[ "$(cat "$repo_root/ACTIVE_VERSION")" == "$(sed -n 's/^  version: "\(.*\)"$/\1/p' "$skill_md")" ]] || fail "ACTIVE_VERSION and SKILL.md metadata.version differ"
  grep -qF -- "\`--ref v$(cat "$repo_root/ACTIVE_VERSION")\` to pin a version" "$repo_root/README.md" || fail "README install example is not pinned to the current version"
  grep -qi 'kis:compass\|kis-compass' "$repo_root/README.md" && fail "README still lists a compass command"
  contains "$repo_root/README.md" '`/kis:init` also writes `kis/intent/compass.md`' || fail "README does not say init writes the compass"

  ruby -rjson -e '
    ids = JSON.parse(File.read(ARGV[0])).fetch("evals").map { |e| e.fetch("id") }
    missing = %w[init-writes-compass plan-reads-compass] - ids
    abort("missing compass evals: #{missing.join(", ")}") unless missing.empty?
  ' "$repo_root/evals/evals.json" || fail "evals/evals.json failed the compass eval check"
fi

echo "compass tests: pass"
