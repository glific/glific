# Glific API collection (Bruno)

`glific_api/` is the reference for Glific's API: every GraphQL query, mutation and
subscription, and the client-facing REST endpoints, as runnable [Bruno](https://www.usebruno.com)
requests with their docs. It uses Bruno's OpenCollection YAML format and needs Bruno **v4.3 or
later**.

## Using it

1. Install Bruno from [usebruno.com/downloads](https://www.usebruno.com/downloads).
2. In Bruno, choose **Open Collection** and pick `api.docs/glific_api`.
3. Pick the `local` or `staging` environment and set `phone` and `password`. The `local`
   environment is prefilled with the seeded admin user.
4. Run **Authentication › Login**. It stores the tokens in `auth_token` and `renewal_token`,
   and every other request sends `auth_token` automatically.

The collection's own docs (open the collection settings, **Docs** tab) cover authentication,
roles, errors, pagination and scalars.

From the command line, with [Bruno CLI](https://www.npmjs.com/package/@usebruno/cli):

```bash
cd api.docs/glific_api && npx @usebruno/cli@4.3.0 run authentication/login.yml tags --env local --insecure
```

## Layout

```
glific_api/
├── opencollection.yml      # collection: name, shared auth, overview docs
├── environments/           # local.yml, staging.yml
└── <area>/                 # one folder per API area, such as contacts/ or flows/
    ├── folder.yml          # folder name, order and overview docs
    └── <request-name>.yml  # one file per operation
```

- Folders are kebab-case and named after the area (`whatsapp-forms`, `contact-fields`).
- A request file is named after the kebab-case of its `info.name`: `Create a tag` is
  `create-a-tag.yml`.
- Inside a folder, `seq` orders requests: list, get, count, then create, update, delete,
  then everything else, then subscriptions.

## Writing a request

Copy the closest request in `tags/` and follow it. Every request has:

- **`info`**: `name` in sentence case starting with a verb (`List tags`, `Get a tag`,
  `Count tags`, `Create a tag`, `Send a session message`), `type` (`graphql` or `http`) and
  `seq`.
- **The operation**: a named GraphQL operation with typed variables, never values written
  into the query. Select the fields a client actually uses, always including `errors { key
  message }` on result types.
- **Variables**: a realistic example that passes validation. Use IDs from the dev seeds where
  you can. Never commit real phone numbers, tokens or keys.
- **Auth**: `auth: inherit` for anything that needs a logged-in user. Leave `auth` out for
  public endpoints such as login. Don't add `authorization`, `Content-Type` or `Accept`
  headers; Bruno and the collection set them.
- **`docs`**, in this order:
  1. One or two sentences on what the operation does and any side effects.
  2. `**Role:** <lowest role>` for GraphQL, from the `Authorize` middleware on the field.
     Mention a feature flag if the field needs one.
  3. `## Arguments`: a table of `Argument | Type | Required | Description`, then one
     `### <InputType>` table per input object or filter.
  4. `## Example response`: a JSON block matching the query in the request.
  5. `## Errors`: what comes back in `errors`, and when a top-level error is returned.

  Write docs from the code (the type module, resolver and context function), not from
  memory. Keep them short: no FAQ or use-case sections.

REST requests follow the same shape, with `## Request body` instead of `## Arguments` and
status codes in `## Errors`.

## Published docs

The `API Docs Site` workflow publishes the collection as a single HTML page to
[glific.github.io/glific](https://glific.github.io/glific/) whenever a change under
`api.docs/` lands on `master`. It runs `npm run site` in `tools/`, which generates the page
with Bruno CLI and includes only the `staging` environment. To preview it locally:

```bash
cd api.docs/tools && npm ci && npm run site
```

Then serve `tools/_site/` over http, for example with `python3 -m http.server -d _site`.

## Keeping it current

A new or changed GraphQL field or REST endpoint ships with its request here, in the same pull
request. The `api-docs` CI job runs the checker in `tools/` on every pull request; run it
locally before pushing:

```bash
cd api.docs/tools && npm ci && npm run schema && npm run validate
```

It confirms Bruno can parse every file, validates each GraphQL request and its variables
against the current schema, checks names, `seq`, auth and the docs sections, and lists every
query, mutation and subscription that has no request yet; a missing request fails the check.
Fields deliberately kept out of the public docs, such as admin-only internals, are listed in
`UNDOCUMENTED` at the top of `validate.js`. Pass folder names to check only those:
`node validate.js ../glific_api contacts flows`.
