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

# The compass is a file init writes, not a command: no command, no reference of its own. Specialist routing is gone.
[[ ! -e "$pkg/commands/compass.md" ]] || fail "commands/compass.md exists; the compass has no command"
[[ ! -e "$pkg/references/product-compass.md" ]] || fail "references/product-compass.md exists; bootstrap.md owns the compass shape"
[[ ! -e "$pkg/references/specialist-routing.md" ]] || fail "references/specialist-routing.md exists; specialist routing was dropped"
grep -rqi 'compass command\|/kis:compass\|kis-compass' "$pkg" && fail "the package still mentions a compass command: $(grep -rli 'compass command\|/kis:compass\|kis-compass' "$pkg" | paste -sd ' ' -)"
grep -rqi 'specialist' "$pkg" && fail "the package still mentions specialists: $(grep -rli 'specialist' "$pkg" | paste -sd ' ' -)"
grep -rqF 'intent/compass.md' "$pkg" && fail "the package still names the old intent/compass.md path: $(grep -rlF 'intent/compass.md' "$pkg" | paste -sd ' ' -)"

# SKILL.md: one line per layer, Reality ranked above Knowledge, and one routing rule.
has "$skill_md" '  knowledge/   stable facts: stack, architecture, design direction, domain terms, constraints, standards, durable decisions; project.md (purpose, audience, problem), compass.md (vision, North Star, principles)' || fail "SKILL.md Knowledge line changed"
has "$skill_md" '  intent/      PRDs, plans, goals, acceptance criteria, user stories, backlog; private/ holds notes git ignores' || fail "SKILL.md Intent line changed"
has "$skill_md" '  reality/     what shipped: features, their behavior, known defects; overview.md summarizes the features' || fail "SKILL.md Reality line changed"
has "$skill_md" '  state/       branches, worktrees, tasks, blockers, commands, status, proof, next action' || fail "SKILL.md State line changed"
has "$skill_md" 'State > Intent > Reality > Knowledge > conversation > repository inspection' || fail "SKILL.md truth hierarchy changed"
contains "$skill_md" 'A bug in what shipped is a defect in Reality, a planned fix goes on the Intent backlog, and a bug in unshipped current work stays in State.' || fail "SKILL.md lost the defect routing"
[[ "$(grep -c 'compass' "$skill_md")" == "1" ]] || fail "SKILL.md says more about the compass than its layer line"

# init asks the direction questions and writes the files; a project without a compass is incomplete.
contains "$init_md" 'then the direction: why it should exist, the vision, the North Star, principles, what not to build, and POC versus MVP.' || fail "init.md does not ask the direction questions"
contains "$init_md" 'A missing `kis/knowledge/compass.md` counts as incomplete, and so does a missing `kis/reality/overview.md` once something has shipped.' || fail "init.md cannot add a compass or overview to an existing project"
contains "$init_md" 'Purpose, audience, and problem go to `kis/knowledge/project.md`; where the product is going goes to `kis/knowledge/compass.md`' || fail "init.md does not split project from compass"
contains "$init_md" 'what has shipped goes to `kis/reality/overview.md`. A new project with nothing shipped has no Reality yet.' || fail "init.md does not route shipped work to Reality"
contains "$bootstrap_md" 'then the direction: why it should exist, the vision, the North Star, principles, what not to build, and POC versus MVP.' || fail "bootstrap.md does not ask the direction questions"
contains "$bootstrap_md" 'purpose, audience, and problem in `knowledge/project.md`, where the product is going in `knowledge/compass.md` (see Compass). Reality starts when something ships.' || fail "bootstrap.md does not write both files"

# bootstrap.md owns the compass shape and its guards; project.md owns why, who and the problem.
has "$bootstrap_md" '## Compass' || fail "bootstrap.md lost the Compass section"
compass_shape="$(awk '/^## Compass$/ {f = 1} f && /^```text$/ {g = 1; next} g && /^```$/ {exit} g {print}' "$bootstrap_md" | paste -sd '|' -)"
[[ "$compass_shape" == "# Compass: <product>||## Vision|## North Star|## Principles|## Not building|## POC vs MVP|### POC (testing)|### MVP (committed)" ]] || fail "bootstrap.md compass shape changed: $compass_shape"
has "$bootstrap_md" '- Never invent metrics, targets, or a North Star. Without one the user can name, write `none yet`.' || fail "bootstrap.md lost the invented-metrics guard"
has "$bootstrap_md" '- Mark a belief that is not yet proven as a hypothesis.' || fail "bootstrap.md lost the hypothesis guard"
contains "$bootstrap_md" 'The vision stays stable while features, technology, and experiments change, so keep those out of the compass.' || fail "bootstrap.md lost the stable-vision rule"
suggested="$(awk '/^## Suggested Files$/ {f = 1} f && /^```text$/ {g = 1; next} g && /^```$/ {exit} g {print}' "$bootstrap_md" | paste -sd '|' -)"
[[ "$suggested" == "kis/|  knowledge/|    project.md|    compass.md|    technical.md|    rules.md|  intent/|    PRD.md|    ImplementationPlan.md|    backlog.md|  reality/|    overview.md|    defects.md|  state/|    current.md" ]] || fail "bootstrap.md suggested files changed: $suggested"
has "$bootstrap_md" 'Product direction   -> knowledge/compass.md' || fail "bootstrap.md document mapping does not send direction to knowledge/compass.md"
has "$bootstrap_md" 'Known defects       -> reality/defects.md' || fail "bootstrap.md document mapping omits defects"

# plan reads both files and routes facts across all four layers.
contains "$plan_md" 'Read `kis/knowledge/project.md` and `kis/knowledge/compass.md` when they exist.' || fail "plan.md does not read project.md and compass.md"
has "$plan_md" 'Reality   = what shipped' || fail "plan.md STRUCTURE omits Reality"
has "$plan_md" '- Reality:' || fail "plan.md output omits the Reality write"

# file-hygiene owns the private-notes rule and how sync writes the stamp.
has "$pkg/references/file-hygiene.md" 'Before writing to `kis/intent/private/`, make sure `.gitignore` covers it: those notes must never be committed.' || fail "file-hygiene.md lost the private-notes rule"
contains "$pkg/references/file-hygiene.md" '- a `Stamp:` line: the verbatim output of `scripts/state-stamp.sh <project root>`' || fail "file-hygiene.md does not own the Stamp line"

# The command lists name no compass command.
project="$tmp_dir/project"
mkdir -p "$project/.agents/skills" "$project/kis/state"
cp -R "$pkg" "$project/.agents/skills/kis"
printf 'Branch: main\nTask: x\nNext: y\n' > "$project/kis/state/current.md"
anchor_out="$("$pkg/hooks/session-anchor.sh" "$project")"
[[ "$(grep -c '^Commands in .agents/skills/kis/commands/: start, plan, act, sync, check, init\.$' <<< "$anchor_out")" == "1" ]] || fail "session anchor command list is wrong"
[[ "$(grep -cxF 'This project uses KIS project memory under `kis/`. Knowledge = stable facts. Intent = goals and plans. Reality = what shipped. State = what is happening now.' <<< "$anchor_out")" == "1" ]] || fail "session anchor layer line is wrong"
"$pkg/scripts/install-anchor.sh" --target "$project" --no-hook >/dev/null
grep -qxF -- '- Commands live in `.agents/skills/kis/commands/`: start, plan, act, sync, check, init.' "$project/AGENTS.md" || fail "AGENTS.md KIS block command list is wrong"
grep -qxF -- 'This project uses KIS memory under `kis/`. Knowledge = stable facts. Intent = goals and plans. Reality = what shipped. State = what is happening now.' "$project/AGENTS.md" || fail "AGENTS.md KIS block layer line is wrong"
install_out="$("$pkg/scripts/install-commands.sh" --target "$project" --host all --codex-prompts-dir "$tmp_dir/codex")"
[[ "$install_out" != *compass* ]] || fail "installer usage lines still name compass"

if [[ "$pkg" == "$repo_root/skills/kis" ]]; then
  # Versions agree (AGENTS.md: ACTIVE_VERSION and metadata.version must match).
  [[ "$(cat "$repo_root/ACTIVE_VERSION")" == "$(sed -n 's/^  version: "\(.*\)"$/\1/p' "$skill_md")" ]] || fail "ACTIVE_VERSION and SKILL.md metadata.version differ"
  grep -qF -- "\`--ref v$(cat "$repo_root/ACTIVE_VERSION")\` to pin a version" "$repo_root/README.md" || fail "README install example is not pinned to the current version"
  grep -qi 'kis:compass\|kis-compass' "$repo_root/README.md" && fail "README still lists a compass command"
  contains "$repo_root/README.md" '`/kis:init` writes `kis/knowledge/project.md`, what the product is for, and `kis/knowledge/compass.md`, where it is going' || fail "README does not say init writes project and compass"
grep -qF 'intent/compass.md' "$repo_root/README.md" "$repo_root/evals/evals.json" && fail "README or evals still name intent/compass.md"

  ruby -rjson -e '
    ids = JSON.parse(File.read(ARGV[0])).fetch("evals").map { |e| e.fetch("id") }
    missing = %w[init-writes-compass plan-reads-compass sync-routes-shipped-work] - ids
    abort("the specialist eval is still present") if ids.include?("standard-mode-specialist-unavailable")
    abort("missing layer evals: #{missing.join(", ")}") unless missing.empty?
  ' "$repo_root/evals/evals.json" || fail "evals/evals.json failed the layer eval check"
fi

echo "compass tests: pass"
