// Creates the "sdd-agent" GitHub App through the GitHub App manifest flow.
// The human only clicks "Create GitHub App" and "Install"; credentials are stored
// outside the repository in ~/.sdd (never commit them).
//
// Usage: node scripts/bootstrap/create-agent-app.mjs --name sdd-agent-dpardora1 --repo dpardora1/OpenSpecsTest
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, cur, i, all) => (cur.startsWith('--') ? [...acc, [cur.slice(2), all[i + 1]]] : acc), [])
);
const appName = args.name ?? 'sdd-agent';
const repo = args.repo ?? '';
const port = Number(args.port ?? 3999);
const outDir = path.join(os.homedir(), '.sdd');
const base = `http://localhost:${port}`;

const manifest = {
  name: appName,
  url: repo ? `https://github.com/${repo}` : 'https://github.com',
  description: 'Identity used by the SDD agents (OpenSpec + GitHub Copilot) to author commits and pull requests.',
  public: false,
  redirect_url: `${base}/callback`,
  setup_url: `${base}/installed`,
  hook_attributes: { url: 'https://example.invalid/webhook', active: false },
  default_events: [],
  default_permissions: {
    contents: 'write',
    pull_requests: 'write',
    issues: 'write',
    workflows: 'write',
    actions: 'read',
    checks: 'read',
    statuses: 'read',
    metadata: 'read',
  },
};

const escapeHtml = (s) => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
const page = (title, body) =>
  `<!doctype html><html><head><meta charset="utf-8"><title>${title}</title></head>` +
  `<body style="font-family:system-ui;max-width:640px;margin:4rem auto">${body}</body></html>`;

fs.mkdirSync(outDir, { recursive: true });
const configPath = path.join(outDir, 'sdd-agent.json');

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, base);
  try {
    if (url.pathname === '/') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(
        page(
          'Create SDD agent app',
          `<h1>Crear GitHub App <code>${appName}</code></h1>` +
            `<p>Se enviará el manifiesto a GitHub. Pulsa <b>Create GitHub App</b> y después <b>Install</b> en el repositorio <code>${repo}</code>.</p>` +
            `<form id="f" action="https://github.com/settings/apps/new" method="post">` +
            `<input type="hidden" name="manifest" value="${escapeHtml(JSON.stringify(manifest))}">` +
            `<button type="submit">Continuar en GitHub</button></form>` +
            `<script>document.getElementById('f').submit()</script>`
        )
      );
      return;
    }

    if (url.pathname === '/callback') {
      const code = url.searchParams.get('code');
      const r = await fetch(`https://api.github.com/app-manifests/${code}/conversions`, {
        method: 'POST',
        headers: { Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' },
      });
      if (!r.ok) throw new Error(`Manifest conversion failed: ${r.status} ${await r.text()}`);
      const app = await r.json();
      fs.writeFileSync(path.join(outDir, 'sdd-agent.pem'), app.pem, { mode: 0o600 });
      const config = {
        app_id: app.id,
        slug: app.slug,
        client_id: app.client_id,
        owner: app.owner?.login,
        html_url: app.html_url,
        repo,
      };
      fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
      console.log(`APP_CREATED ${app.slug} (id ${app.id})`);
      res.writeHead(302, { Location: `${app.html_url}/installations/new` });
      res.end();
      return;
    }

    if (url.pathname === '/installed') {
      const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
      config.installation_id = Number(url.searchParams.get('installation_id'));
      fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
      console.log(`APP_INSTALLED installation ${config.installation_id}`);
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(page('Done', `<h1>✅ Listo</h1><p>La App <code>${config.slug}</code> está instalada. Ya puedes cerrar esta pestaña.</p>`));
      setTimeout(() => server.close(() => process.exit(0)), 500);
      return;
    }

    res.writeHead(404).end();
  } catch (err) {
    console.error(err);
    res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' }).end(String(err));
  }
});

server.listen(port, () => console.log(`LISTENING ${base}`));
