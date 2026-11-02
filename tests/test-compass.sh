#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkg="${1:-$repo_root/skills/kis}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "$*" >&2
  exit 1
}

has() { grep -qxF -- "$2" "$1"; }
contains() { grep -qF -- "$2" "$1"; }

command_md="$pkg/commands/compass.md"
reference_md="$pkg/references/product-compass.md"
plan_md="$pkg/commands/plan.md"
skill_md="$pkg/SKILL.md"

[[ -f "$command_md" ]] || fail "commands/compass.md is missing"
[[ -f "$reference_md" ]] || fail "references/product-compass.md is missing"

# Command frontmatter follows the other commands: description and argument-hint, between the fences.
[[ "$(sed -n 1p "$command_md")" == "---" ]] || fail "compass.md does not open with frontmatter"
frontmatter="$(awk 'NR>1 && /^---$/ {exit} NR>1 {print}' "$command_md")"
[[ "$(grep -c '^description: .\+' <<< "$frontmatter")" == "1" ]] || fail "compass.md needs exactly one description"
[[ "$(grep -c '^argument-hint: \[.\+\]$' <<< "$frontmatter")" == "1" ]] || fail "compass.md needs exactly one argument-hint"
has "$command_md" "# KIS Compass" || fail "compass.md heading is missing"
contains "$command_md" '`$ARGUMENTS`' || fail "compass.md does not take the user's arguments"

# The command stands alone: it names the skill, and the one owner of the compass rules.
contains "$command_md" '.agents/skills/kis/SKILL.md' || fail "compass.md does not point at SKILL.md"
contains "$command_md" '.agents/skills/kis/references/product-compass.md' || fail "compass.md does not point at the reference"

# Behaviour contract, one anchored phrase per required behaviour.
for phrase in \
  'Do not implement anything in this command.' \
  '3. Inspect existing product documentation before asking anything:' \
  'One consequential question at a time, waiting for each answer.' \
  'Give your recommended answer and the tradeoff with every question.' \
  '6. Challenge vague intent,' \
  'Keep facts, hypotheses, experiments, and confirmed decisions apart' \
  'Invent no metrics, thresholds, sample sizes, research, quotes, or market evidence;' \
  '8. Separate the POC from the MVP:' \
  '9. Present the proposed compass:' \
  'Only after explicit confirmation, create or update `kis/intent/compass.md`' \
  'Preserve earlier decisions unless the user explicitly revised them' \
  'no edits to the PRD, plan, State, or Knowledge.' \
  'it is not confirmation of a compass the user has not seen.' \
  'Stop after the compass is written.' \
  'If the user does not confirm, write nothing.'; do
  grep -qF -- "$phrase" "$command_md" || fail "compass.md lost required behaviour: $phrase"
done

# The write comes after the confirmation step, never before.
confirm_line="$(grep -nF '9. Present the proposed compass:' "$command_md" | cut -d: -f1)"
write_line="$(grep -nF 'Only after explicit confirmation, create or update' "$command_md" | cut -d: -f1)"
[[ -n "$confirm_line" && -n "$write_line" && "$confirm_line" -lt "$write_line" ]] || fail "the confirmation step must precede the write"

# The only KIS file the command may write is kis/intent/compass.md.
mentioned="$(grep -oP '(?<![A-Za-z0-9_./-])kis/[a-z]+/[A-Za-z0-9_.*-]+\.md' "$command_md" | sort -u)"
[[ "$mentioned" == "kis/intent/compass.md" ]] || fail "compass.md names a KIS file other than kis/intent/compass.md: $mentioned"

# Reference: every section, every evidence tag, the metric guard, and the stable/changeable split.
for section in 'Intent' 'Audience and Problem' 'Vision' 'Core Promise' 'Strategy' 'Principles' 'Boundaries' 'Success Signals' 'Discovery' 'POC and MVP'; do
  grep -q "^| $section | " "$reference_md" || fail "reference lost the $section section"
done
for tag in '[fact]' '[hypothesis]' '[experiment]' '[decision]'; do
  awk -v t="$tag " 'index($0, t) == 1 { found = 1 } END { exit !found }' "$reference_md" || fail "reference lost the $tag evidence tag"
done
has "$reference_md" 'The compass lives at `kis/intent/compass.md`. It keeps direction steady while features, technology, and experiments change. It informs planning and replaces nothing.' || fail "reference lost its location and role statement"
contains "$reference_md" 'The vision stays relatively stable.' || fail "reference lost the stable-vision principle"
contains "$reference_md" 'A POC may contain temporary functionality that never becomes part of the MVP.' || fail "reference lost the POC principle"
contains "$reference_md" 'only when the user can name the repeatable moment of customer value' || fail "reference lost the North Star guard"
contains "$reference_md" 'Never propose targets, baselines, thresholds, or sample sizes the user did not give.' || fail "reference lost the invented-metric guard"
contains "$reference_md" 'Do not invent metrics, research, user quotes, market sizes, competitors, or evidence.' || fail "reference lost the invented-evidence guard"
contains "$reference_md" 'Only the user'"'"'s confirmation makes a `[decision]`.' || fail "reference lost the decision rule"
contains "$reference_md" 'Confirming the compass confirms its choices, not its beliefs.' || fail "reference lost the choice-versus-belief rule"
contains "$reference_md" 'A belief about the world (what the audience needs, how people will behave, that the value is real) stays a `[hypothesis]` until evidence supports it' || fail "reference lost the belief-stays-hypothesis rule"
contains "$reference_md" 'Every bullet carries exactly one tag, except the `North Star: none yet` line:' || fail "reference lost the one-tag rule"
contains "$reference_md" 'Write only after the user confirms the proposed compass.' || fail "reference lost the confirm-before-write rule"
contains "$reference_md" 'it does not confirm a compass the user has not seen.' || fail "reference lost the skip-the-interview is not confirmation rule"
contains "$reference_md" 'Add `## Revisions` with the first revision, not before.' || fail "reference lost the no-empty-Revisions rule"
contains "$reference_md" 'Preserve existing decisions.' || fail "reference lost the preserve-decisions rule"
contains "$reference_md" 'Point to the owner instead of copying.' || fail "reference lost the no-duplication rule"
contains "$reference_md" 'Stop after writing. Do not start implementing.' || fail "reference lost the stop rule"
has "$reference_md" '## Revisions' || fail "reference file shape lost the Revisions section"

# One owner per fact: the tags and the rules live in the reference, not in SKILL.md.
for tag in '[hypothesis]' '[experiment]'; do
  contains "$skill_md" "$tag" && fail "SKILL.md restates the evidence tag $tag"
done
contains "$skill_md" '[product-compass.md](references/product-compass.md)' || fail "SKILL.md does not link the reference"
contains "$skill_md" '`compass` (product direction' || fail "SKILL.md does not list the compass command"
[[ "$(grep -c 'compass' "$skill_md")" -le 4 ]] || fail "SKILL.md grew past a short compass pointer"

# /kis:plan consults the compass when relevant and does not edit it.
contains "$plan_md" 'read it and `.agents/skills/kis/references/product-compass.md`' || fail "plan.md does not read the compass"
contains "$plan_md" 'Do not override the compass or edit it here; a change of direction goes through the compass command.' || fail "plan.md lost the do-not-override rule"
contains "$plan_md" 'place work as POC or MVP' || fail "plan.md does not place work as POC or MVP"

# The reference doc lists the command.
contains "$pkg/references/commands.md" '| `compass.md` |' || fail "references/commands.md does not list compass.md"

# Installation: the real package, every host with an adapter.
project="$tmp_dir/project"
codex_dir="$tmp_dir/codex-prompts"
mkdir -p "$project/.agents/skills"
cp -R "$pkg" "$project/.agents/skills/kis"
install_out="$("$pkg/scripts/install-commands.sh" --target "$project" --host all --codex-prompts-dir "$codex_dir")"

[[ "$install_out" == *"/kis:compass"* ]] || fail "Claude usage line omits /kis:compass"
[[ "$(grep -c '^Pi usage:.* /kis-compass ' <<< "$install_out")" == "1" ]] || fail "Pi usage line omits /kis-compass"
[[ "$(grep -c '^OpenCode usage:.* /kis-compass ' <<< "$install_out")" == "1" ]] || fail "OpenCode usage line omits /kis-compass"
[[ "$(grep -c '^Codex usage:.* /prompts:kis-compass ' <<< "$install_out")" == "1" ]] || fail "Codex usage line omits /prompts:kis-compass"

installed="$project/.agents/skills/kis/commands/compass.md"
[[ -L "$project/.claude/commands/kis" ]] || fail "Claude command link missing"
cmp -s "$project/.claude/commands/kis/compass.md" "$installed" || fail "Claude does not resolve /kis:compass to the packaged command"
[[ "$(readlink "$project/.pi/prompts/kis-compass.md")" == "../../.agents/skills/kis/commands/compass.md" ]] || fail "Pi link for compass is wrong"
cmp -s "$project/.pi/prompts/kis-compass.md" "$installed" || fail "Pi does not resolve /kis-compass to the packaged command"
[[ "$(readlink "$project/.opencode/command/kis-compass.md")" == "../../.agents/skills/kis/commands/compass.md" ]] || fail "OpenCode link for compass is wrong"
cmp -s "$project/.opencode/command/kis-compass.md" "$installed" || fail "OpenCode does not resolve /kis-compass to the packaged command"
cmp -s "$codex_dir/kis-compass.md" "$installed" || fail "Codex prompt kis-compass.md is not a copy of the packaged command"

# Every shipped command reaches every host, so a command cannot be added without an adapter.
for file in "$pkg"/commands/*.md; do
  name="$(basename "$file" .md)"
  [[ -e "$project/.claude/commands/kis/$name.md" ]] || fail "Claude is missing $name"
  [[ -e "$project/.pi/prompts/kis-$name.md" ]] || fail "Pi is missing $name"
  [[ -e "$project/.opencode/command/kis-$name.md" ]] || fail "OpenCode is missing $name"
  [[ -e "$codex_dir/kis-$name.md" ]] || fail "Codex is missing $name"
done

"$pkg/scripts/install-commands.sh" --target "$project" --host all --codex-prompts-dir "$codex_dir" --remove >/dev/null
[[ ! -e "$project/.pi/prompts/kis-compass.md" && ! -L "$project/.pi/prompts/kis-compass.md" ]] || fail "--remove left the Pi compass link"
[[ ! -e "$project/.opencode/command/kis-compass.md" && ! -L "$project/.opencode/command/kis-compass.md" ]] || fail "--remove left the OpenCode compass link"
[[ ! -e "$codex_dir/kis-compass.md" ]] || fail "--remove left the Codex compass prompt"

# Re-anchor layer: the session hook and the instruction block (Pi, OpenCode, Codex, Antigravity) list compass.
mkdir -p "$project/kis/state"
printf 'Branch: main\nTask: x\nNext: y\n' > "$project/kis/state/current.md"
anchor_out="$("$pkg/hooks/session-anchor.sh" "$project")"
[[ "$(grep -c '^Commands in .agents/skills/kis/commands/: start, plan, compass, act, sync, check, init\.$' <<< "$anchor_out")" == "1" ]] || fail "session anchor does not list compass"
[[ "$(wc -l <<< "$anchor_out")" -le 20 ]] || fail "session anchor outgrew its 20 line budget"

"$pkg/scripts/install-anchor.sh" --target "$project" --no-hook >/dev/null
grep -qF 'start, plan, compass, act, sync, check, init.' "$project/AGENTS.md" || fail "AGENTS.md KIS block does not list compass"

# Versions agree (AGENTS.md: ACTIVE_VERSION and metadata.version must match).
if [[ "$pkg" == "$repo_root/skills/kis" ]]; then
  [[ "$(cat "$repo_root/ACTIVE_VERSION")" == "$(sed -n 's/^  version: "\(.*\)"$/\1/p' "$skill_md")" ]] || fail "ACTIVE_VERSION and SKILL.md metadata.version differ"
  grep -qF -- "\`--ref v$(cat "$repo_root/ACTIVE_VERSION")\` to pin a version" "$repo_root/README.md" || fail "README install example is not pinned to the current version"
fi

# Evaluation cases: structure and the scenarios the compass must be judged on.
evals_dir="$repo_root/evals"
if [[ "$pkg" == "$repo_root/skills/kis" ]]; then
  ruby -rjson -e '
    evals = JSON.parse(File.read(ARGV[0])).fetch("evals")
    ids = evals.map { |e| e.fetch("id") }
    abort("duplicate eval ids") unless ids.uniq.size == ids.size
    evals.each do |e|
      %w[id prompt expected_output].each { |k| abort("#{e["id"]}: empty #{k}") if e[k].to_s.strip.empty? }
      a = e["assertions"]
      abort("#{e["id"]}: needs at least 3 assertions") unless a.is_a?(Array) && a.size >= 3 && a.all? { |x| x.is_a?(String) && !x.strip.empty? }
    end
    required = %w[compass-new-product compass-existing-direction compass-revise compass-poc-vs-mvp compass-no-invented-evidence compass-no-duplication compass-confirm-before-write plan-uses-compass]
    missing = required - ids
    abort("missing compass evals: #{missing.join(", ")}") unless missing.empty?
    puts "evals: #{evals.size} cases, #{required.size} compass"
  ' "$evals_dir/evals.json" >/dev/null || fail "evals/evals.json failed the compass eval check"

  ruby -rjson -e '
    q = JSON.parse(File.read(ARGV[0]))
    abort("every query needs query and should_trigger") unless q.all? { |x| x["query"].to_s != "" && [true, false].include?(x["should_trigger"]) }
    compass = q.select { |x| x["query"] =~ /compass|product direction|POC|MVP/i }
    abort("need compass trigger queries that should trigger") unless compass.count { |x| x["should_trigger"] } >= 3
    abort("need compass-adjacent queries that should not trigger") unless compass.count { |x| !x["should_trigger"] } >= 1
  ' "$evals_dir/trigger-queries.json" || fail "evals/trigger-queries.json failed the compass trigger check"
fi

echo "compass tests: pass"
