// Validates the agent customization files and workflows of the repository:
//   - YAML frontmatter of .github/agents/*.agent.md, .github/skills/*/SKILL.md, .github/prompts/*.prompt.md,
//     .github/instructions/*.instructions.md (parses and has the required keys)
//   - every .github/workflows/*.yml parses; github-script steps compile; third-party actions are pinned by SHA
//   - every agent referenced in a conductor's `agents:` list exists
// Uses the 'yaml' package shipped with the OpenSpec CLI (NODE_PATH = <npm root -g>/@fission-ai/openspec/node_modules),
// so no extra dependency is needed. Prints one line per problem and exits 1 if any.
'use strict';
const fs = require('fs');
const path = require('path');
const YAML = require('yaml');

const root = process.argv[2] || process.cwd();
const problems = [];
const files = [];
const walk = (dir) => {
  if (!fs.existsSync(dir)) return;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (/\.(agent|prompt|instructions)\.md$|^SKILL\.md$/.test(e.name)) files.push(p);
  }
};
['.github/agents', '.github/skills', '.github/prompts', '.github/instructions'].forEach((d) => walk(path.join(root, d)));

const required = { agent: ['name', 'description'], skill: ['name', 'description'], prompt: ['description'], instructions: ['description', 'applyTo'] };
const agentNames = new Set();
const conductors = [];
for (const f of files) {
  const rel = path.relative(root, f).replace(/\\/g, '/');
  const text = fs.readFileSync(f, 'utf8').replace(/^\uFEFF/, '');
  const m = text.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!m) { problems.push(`${rel}: missing YAML frontmatter`); continue; }
  let data;
  try { data = YAML.parse(m[1]) || {}; } catch (e) { problems.push(`${rel}: invalid YAML (${e.message.split('\n')[0]})`); continue; }
  const kind = rel.endsWith('.agent.md') ? 'agent' : rel.endsWith('SKILL.md') ? 'skill' : rel.endsWith('.prompt.md') ? 'prompt' : 'instructions';
  for (const k of required[kind]) if (data[k] === undefined || data[k] === '') problems.push(`${rel}: missing '${k}'`);
  if (kind === 'skill' && data.name && data.name !== path.basename(path.dirname(f))) problems.push(`${rel}: name '${data.name}' != folder`);
  if (kind === 'agent') {
    agentNames.add(data.name);
    agentNames.add(path.basename(f, '.agent.md'));
    if (Array.isArray(data.agents)) conductors.push({ rel, agents: data.agents });
  }
}
for (const c of conductors) for (const a of c.agents) if (a !== '*' && !agentNames.has(a)) problems.push(`${c.rel}: subagent '${a}' does not exist`);

const wfDir = path.join(root, '.github/workflows');
let workflows = 0;
if (fs.existsSync(wfDir)) {
  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
  for (const name of fs.readdirSync(wfDir).filter((n) => /\.ya?ml$/.test(n))) {
    workflows++;
    const rel = `.github/workflows/${name}`;
    let wf;
    try { wf = YAML.parse(fs.readFileSync(path.join(wfDir, name), 'utf8')); } catch (e) { problems.push(`${rel}: invalid YAML (${e.message.split('\n')[0]})`); continue; }
    for (const [jobId, job] of Object.entries(wf.jobs || {})) {
      for (const step of job.steps || []) {
        if (step.uses && !step.uses.startsWith('./') && !/@[0-9a-f]{40}$/.test(step.uses.split(' ')[0])) problems.push(`${rel}: job '${jobId}' uses '${step.uses}' not pinned by commit SHA`);
        if (step.uses && step.uses.startsWith('actions/github-script@') && step.with && step.with.script) {
          try { new AsyncFunction('github', 'context', 'core', 'glob', 'io', 'exec', 'require', step.with.script); } catch (e) { problems.push(`${rel}: job '${jobId}' github-script does not compile (${e.message})`); }
        }
      }
    }
  }
}

problems.forEach((p) => console.log(`ERROR ${p}`));
console.log(`customization files=${files.length} workflows=${workflows} problems=${problems.length}`);
process.exit(problems.length ? 1 : 0);
