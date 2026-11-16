// Builds the static API docs site into _site/index.html with Bruno CLI.
//
// Usage, from api.docs/tools:
//   npm run site
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const BRUNO_CLI = '@usebruno/cli@4.3.0';
const COLLECTION = path.join(__dirname, '..', 'glific_api');
const OUTPUT = path.join(__dirname, '_site', 'index.html');
const VIEWER_TAG = '<script src="https://cdn.usebruno.com/api-docs/api-docs.js"></script>';

// Bruno's CDN viewer now exports OpenCollectionPlayground.OpenCollectionRenderer, while the
// page CLI 4.3.0 generates still calls `new window.OpenCollection(...)`.
const VIEWER_ALIAS =
  '<script>window.OpenCollection = window.OpenCollection || ' +
  '(window.OpenCollectionPlayground && window.OpenCollectionPlayground.OpenCollectionRenderer);</script>';

fs.mkdirSync(path.dirname(OUTPUT), { recursive: true });

execFileSync(
  'npx',
  ['--yes', BRUNO_CLI, 'docs', 'generate', '--envs', 'staging', '--output', OUTPUT],
  { cwd: COLLECTION, stdio: 'inherit' }
);

const html = fs.readFileSync(OUTPUT, 'utf8');
if (!html.includes(VIEWER_TAG)) {
  console.error(`The generated page no longer loads ${VIEWER_TAG}; check the viewer alias.`);
  process.exit(1);
}
fs.writeFileSync(OUTPUT, html.replace(VIEWER_TAG, `${VIEWER_TAG}\n${VIEWER_ALIAS}`));
console.log(`Built ${path.relative(process.cwd(), OUTPUT)}`);
