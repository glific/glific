// Checks the Bruno collection: Bruno can parse every file, each GraphQL request and its
// variables are valid against the schema, and requests follow api.docs/bruno/README.md.
//
// Usage, from api.docs/bruno/tools:
//   npm install
//   npm run schema            # dumps the GraphQL schema to schema.json (needs mix)
//   npm run validate          # whole collection, plus the root fields no request covers
//   node validate.js ../glific_api contacts flows   # only these folders
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
const fsx = require('@usebruno/filestore');
const {
  buildClientSchema,
  parse,
  validate,
  getOperationAST,
  getVariableValues
} = require('graphql');

const SCHEMA_JSON = process.env.SCHEMA_JSON || path.join(__dirname, 'schema.json');

// Root fields deliberately left out of the public collection.
const UNDOCUMENTED = {
  query: ['organizationGroups'],
  mutation: [],
  subscription: []
};
const args = process.argv.slice(2);
const coverage = args.includes('--coverage');
const [root, ...onlyFolders] = args.filter((a) => a !== '--coverage');

const intro = JSON.parse(fs.readFileSync(SCHEMA_JSON, 'utf8'));
const schema = buildClientSchema(intro.data || intro);

const kebab = (s) =>
  s
    .toLowerCase()
    .replace(/['’]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');

const problems = [];
const covered = { query: new Set(), mutation: new Set(), subscription: new Set() };
let checked = 0;

const walk = (dir) =>
  fs.readdirSync(dir).flatMap((f) => {
    const p = path.join(dir, f);
    return fs.statSync(p).isDirectory() ? walk(p) : [p];
  });

const folders = fs
  .readdirSync(root)
  .filter((f) => fs.statSync(path.join(root, f)).isDirectory() && f !== 'environments')
  .filter((f) => onlyFolders.length === 0 || onlyFolders.includes(f));

for (const folder of folders) {
  const files = walk(path.join(root, folder));
  const seqs = new Map();
  if (!files.some((f) => path.basename(f) === 'folder.yml')) problems.push(`${folder}: missing folder.yml`);

  for (const file of files) {
    const rel = path.relative(root, file);
    const err = (m) => problems.push(`${rel}: ${m}`);
    if (!file.endsWith('.yml')) {
      err('not a .yml file');
      continue;
    }
    const text = fs.readFileSync(file, 'utf8');
    let raw;
    try {
      raw = yaml.load(text);
    } catch (e) {
      err(`invalid YAML: ${e.message.split('\n')[0]}`);
      continue;
    }

    if (path.basename(file) === 'folder.yml') {
      try {
        fsx.parseFolder(text, { format: 'yml' });
      } catch (e) {
        err(`Bruno cannot parse folder: ${e.message}`);
      }
      if (!raw.docs || !raw.docs.content) err('folder.yml has no docs');
      continue;
    }

    checked++;
    let req;
    try {
      req = fsx.parseRequest(text, { format: 'yml' });
    } catch (e) {
      err(`Bruno cannot parse request: ${e.message}`);
      continue;
    }

    const info = raw.info || {};
    if (!info.name) err('missing info.name');
    if (info.name && kebab(info.name) + '.yml' !== path.basename(file))
      err(`file name should be ${kebab(info.name)}.yml`);
    if (typeof info.seq !== 'number') err('missing info.seq');
    else {
      const key = `${path.dirname(file)}:${info.seq}`;
      if (seqs.has(key)) err(`seq ${info.seq} also used by ${seqs.get(key)}`);
      seqs.set(key, path.basename(file));
    }

    const block = raw.graphql || raw.http;
    if (!block) {
      err('no graphql or http block');
      continue;
    }
    if (raw.graphql && block.auth !== 'inherit') err('graphql requests must use auth: inherit');
    if (block.auth !== undefined && block.auth !== 'inherit')
      err('auth must be `inherit`, or omitted for a public endpoint');
    if (!raw.docs || String(raw.docs).trim().length < 40) err('missing or very short docs');
    else if (!/\*\*Role:\*\*/.test(raw.docs) && raw.graphql) err('docs missing **Role:** line');
    if (!/## Example response/.test(raw.docs || '')) err('docs missing "## Example response"');
    if (!/## Errors/.test(raw.docs || '')) err('docs missing "## Errors"');
    for (const h of block.headers || []) {
      const name = String(h.name).toLowerCase();
      if (name === 'content-type' || name === 'accept' || (name === 'authorization' && block.auth === 'inherit'))
        err(`redundant header ${h.name}`);
    }

    if (raw.graphql) {
      const q = req.request.body.graphql.query;
      let doc;
      try {
        doc = parse(q);
      } catch (e) {
        err(`GraphQL syntax: ${e.message}`);
        continue;
      }
      const errors = validate(schema, doc);
      errors.forEach((e) => err(`GraphQL: ${e.message}`));
      const op = getOperationAST(doc);
      if (!op) {
        err('document must contain exactly one operation');
        continue;
      }
      for (const sel of op.selectionSet.selections) {
        if (sel.kind === 'Field') covered[op.operation].add(sel.name.value);
      }
      const varsText = req.request.body.graphql.variables;
      let vars = {};
      if (varsText && varsText.trim()) {
        try {
          vars = JSON.parse(varsText.replace(/{{\s*(\w+)\s*}}/g, 'X'));
        } catch (e) {
          err(`variables are not valid JSON: ${e.message}`);
          continue;
        }
      }
      if (errors.length === 0) {
        const res = getVariableValues(schema, op.variableDefinitions || [], vars);
        (res.errors || []).forEach((e) => err(`variables: ${e.message}`));
      }
    }
  }
}

if (coverage) {
  const roots = { query: schema.getQueryType(), mutation: schema.getMutationType(), subscription: schema.getSubscriptionType() };
  for (const [kind, type] of Object.entries(roots)) {
    if (!type) continue;
    const skip = UNDOCUMENTED[kind];
    const fields = Object.keys(type.getFields()).filter((f) => !skip.includes(f));
    const missing = fields.filter((f) => !covered[kind].has(f));
    console.log(`\n${kind}: ${fields.length - missing.length}/${fields.length} covered (${skip.length} excluded)`);
    missing.forEach((f) => problems.push(`${kind} ${f} has no request`));
    skip.filter((f) => covered[kind].has(f)).forEach((f) => problems.push(`${kind} ${f} is excluded but has a request`));
  }
}

console.log(`\nchecked ${checked} requests in ${folders.length} folders, ${problems.length} problems`);
problems.forEach((p) => console.log(`  - ${p}`));
process.exit(problems.length ? 1 : 0);
