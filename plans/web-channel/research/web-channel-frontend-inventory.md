# Research — `glific-web-channel` frontend inventory

**Captured:** 2026-08-28 · Branch `web-channel-prototype`, HEAD `604aac2` · working tree clean

An inventory of what exists **today**, not a proposal. Source material for
[tech-design.md](../tech-design.md) §4.1, §4.7–4.10 and §4.12.

~3,100 LOC across 41 source files. Test suite passes: **8 files / 67 tests** in 1.7 s.

---

## 1. Stack

| Package | Range | Installed |
|---|---|---|
| `react` / `react-dom` | ^19.2.8 | 19.2.8 |
| `vite` | ^8.2.0 | 8.2.0 |
| `typescript` | ~6.0.2 | 6.0.3 |
| `tailwindcss` + `@tailwindcss/vite` | ^4.3.3 | 4.3.3 |
| `phoenix` (+ `@types/phoenix`) | ^1.8.9 | 1.8.9 |
| `axios` | ^1.19.0 | 1.19.0 |
| `radix-ui` (unified package) | ^1.6.7 | 1.6.7 |
| `shadcn` | ^4.16.0 | 4.16.0 |
| `react-hook-form` + `@hookform/resolvers` | ^7.83.0 | 7.83.0 |
| `zod` | ^4.4.3 | 4.4.3 |
| `react-router` (v8, not react-router-dom) | ^8.3.0 | 8.3.0 |
| `lucide-react` | ^1.28.0 | 1.28.0 |
| `@fontsource-variable/geist` | ^5.3.0 | self-hosted font |

Dev: `vitest` 4.1.10, `@vitest/coverage-v8`, `jsdom` 30, `@testing-library/*`, `oxlint` 1.75,
`vite-plugin-mkcert` 2.1, `@vitejs/plugin-react` 6.

- **Package manager: yarn** (lockfile v1). Node pinned by `.tool-versions`: `nodejs 22.23.1`.
- **Linter is oxlint**, not ESLint (`.oxlintrc.json`, two rules). No Prettier config.
- **No** apollo/graphql, no date library (native `Intl`), no state manager.

**shadcn vendoring is hybrid and non-default.** `components.json` sets `"style": "radix-nova"`,
`"baseColor": "neutral"`, `"cssVariables": true`, `"tailwind.config": ""` (empty → CSS-first).
Components are copied into `src/components/ui/`: `button`, `card`, `dialog`, `input`, `label`,
`scroll-area` — six files. Unusually, the `shadcn` npm package is a **runtime dependency** whose
stylesheet is imported (`src/index.css:3` → `@import "shadcn/tailwind.css"`; 629 lines of
`@custom-variant` and scroll-fade utilities, **no colour tokens**). Radix primitives actually used:
`Slot`, `Dialog`, `Label`, `ScrollArea`.

## 2. Structure

```
glific-web-channel/
├── index.html            # <title>Glific — Chat</title>, lang="en"
├── components.json, .oxlintrc.json, .tool-versions, vite.config.ts
├── .env, .env.example    # gitignored except .env.example
├── Dockerfile, nginx.conf, bunnyshell.yaml, BUNNYSHELL.md
├── public/favicon.svg    # hardcoded Glific mark (#863bff)
└── src/
    ├── main.tsx          # createRoot + <StrictMode><BrowserRouter><App/>
    ├── App.tsx           # routing + auth guards
    ├── config.ts         # all backend endpoint URLs
    ├── index.css         # ALL theming lives here (130 lines)
    ├── routes/           # Login.tsx (131), Chat.tsx (476) + tests
    ├── components/
    │   ├── chat/         # MessageBubble, InteractiveMessage, EditName
    │   │   └── blocks/   # BlocksMessage, registry, primitives, values,
    │   │                 # ImagePanel, Carousel, FormBlock, FallbackCard
    │   └── ui/           # 6 shadcn components
    ├── hooks/useAudioRecorder.ts
    ├── lib/              # utils.ts (cn), whatsapp.tsx (markup→JSX, time fmt)
    ├── services/         # webChannelSocket.ts (239), webChannelAuth.ts (78)
    └── test/setup.ts
```

Routing is three routes only — `/login`, `/chat`, `*` → `/chat`. Guards read
`getWebChannelToken()` at render time. **No layout component, no nested routes, no error boundary,
no 404 page.** Socket code lives entirely in `services/webChannelSocket.ts`; no context/provider.

## 3. Component inventory

**Auth** — `routes/Login.tsx`: two-step phone → OTP (react-hook-form + zodResolver, but
`z.string().trim().min(1)` only, i.e. **no phone-format or OTP-length validation**). Shows
`"powered by Glific"` and a hardcoded `"Prototype: use 9999"` (line 111).

**Chat** — `routes/Chat.tsx`: header (EditName + connection status + Logout), reverse-infinite scroll
(`PAGE_SIZE = 100`, `load_more` at offset), ResizeObserver bottom-pinning, optimistic
`local-<timestamp>` bubbles with an id-dedupe `Set`.

**Composer** — inline inside `Chat.tsx`, not extracted. Text input with Enter-to-send; attach
(`accept="audio/*,video/*,image/*,application/pdf"`, `MAX_FILE_BYTES = 15 MB`); location via
`navigator.geolocation`; mic + recording bar driven by `hooks/useAudioRecorder.ts` (probes
`audio/webm;codecs=opus` → `audio/mp4` for iOS Safari).

**Layout** — none as a component. `Chat` hardcodes `mx-auto flex h-[100svh] w-full max-w-2xl flex-col`.

| Message type | Where | Notes |
|---|---|---|
| text | `MessageBubble` → `lib/whatsapp.tsx` | `*bold* _italic_ ~strike~`, autolink, `\n`→`<br>`. XSS-safe (React nodes, no `dangerouslySetInnerHTML`) |
| image / video / audio / document | `MediaContent` | requires `message.media.url` **and** matching `message.type` |
| location | `LocationContent` | body is a Google Maps URL, shown as a MapPin link |
| quick_reply | `InteractiveMessage` → `QuickReply` | optional media header, option buttons |
| list | `ListMessage` | Radix `Dialog` + `ScrollArea`, sections + options |
| location_request_message | `LocationRequest` | geolocation → replies `"lat, lng"` as text |
| blocks | `blocks/BlocksMessage.tsx` + `registry.ts` | built-ins `glific/image-panel`, `glific/carousel`, `glific/form`; unknown → `FallbackCard`. Registry allows runtime `register('tap/attendance', …)` |

**Not rendered:** sticker, contact/vcard, template previews, reactions, read receipts, typing
indicators, message grouping, date separators, avatars, reply-quotes. Interactive/blocks rendering is
gated to `flow === 'outbound'` (`MessageBubble.tsx:63`), so a persisted inbound `blocks_response`
shows as plain summary text.

## 4. Theming — the key section

**Tailwind v4 is CSS-first.** No `tailwind.config.*` and no `postcss.config.*` anywhere; the plugin is
`@tailwindcss/vite`. Everything lives in `src/index.css` (130 lines).

- `@theme inline` (8–49) maps utilities onto CSS vars: `--color-{background,foreground,card,popover,primary,secondary,muted,accent,destructive,border,input,ring}` (+ `-foreground` variants), `--color-chart-1..5`, 8 `--color-sidebar*` (**unused — no sidebar**), `--radius-sm..4xl`, `--font-sans: 'Geist Variable'`.
- `:root` (51–84) holds raw values — all achromatic `oklch(… 0 0)` greys, e.g. `--primary: oklch(0.205 0 0)` (near-black), `--radius: 0.625rem`. The only chromatic value is `--destructive`.
- `@layer base` (120–130) applies `border-border`, `bg-background text-foreground`, `font-sans`.

**Dark mode: defined but unreachable.** `@custom-variant dark (&:is(.dark *))` and a full `.dark {…}`
block (86–118) exist, but **nothing ever adds the `dark` class**. Grepping all of `src/` and
`index.html` for `classList`, `documentElement`, `'dark'`, or `prefers-color-scheme` returns nothing.

**Per-organisation branding: essentially none.** The single exception is the org *name string*:

```ts
// src/config.ts:16-17
export const ORGANIZATION_NAME = `${API_BASE}/v1/session/name`;
```
```tsx
// src/routes/Login.tsx:29,36-44,75-76
const [orgName, setOrgName] = useState('Glific');
useEffect(() => { axios.post(ORGANIZATION_NAME)
  .then(({ data }) => { if (data?.data?.name) setOrgName(data.data.name); })
  .catch(() => {}); }, []);
<div className="text-xl font-semibold">{orgName}</div>
<div className="text-xs text-muted-foreground">powered by Glific</div>
```

**None of these exist:** logo per org, brand colour (build-time or runtime), font override,
`/theme` or `/branding` fetch, `VITE_*` branding vars, `<style>` injection, runtime CSS-var override,
theme provider/context, `data-theme` attribute, org shortcode anywhere in the client. The org name is
also *not* shown on the chat screen — that header shows the **contact's own** name (default `'You'`).

**What makes theming easy:** the entire palette funnels through ~20 CSS custom properties, and app
code uses only token utilities. Grepping all of `src/` for hex/rgb/hsl/oklch literals or inline
`style={{…}}` finds **zero** outside `index.css`. The only non-token colour utilities in the whole app
are `bg-black/10` and `dark:bg-white/10` on the inline-code span in `lib/whatsapp.tsx:18`. A runtime
override of `--primary`/`--background`/`--radius`/`--font-sans` retheme nearly everything, including
the sent-message bubble (`bg-primary text-primary-foreground`, `MessageBubble.tsx:77`).

**Caveats:** (a) the `dark` variant is class-based on an ancestor, so theming must decide who sets it;
(b) `--primary` is near-black, so an org accent needs a matching `--primary-foreground` or contrast
breaks; (c) values are `oklch()` — a hex from an admin form needs conversion; (d) override the *raw*
vars, not the `--color-*` aliases compiled through `@theme inline`; (e) `index.html`'s title, the
favicon and `"powered by Glific"` are static and each need their own hook; (f) the current
Bunnyshell/Docker model bakes `VITE_*` at build time, so build-time theming means a build per NGO.

## 5. Configuration and deployment

- **No `vercel.json`, no Netlify/Cloudflare config, and no `.github/` directory at all — there is no CI in this repo.**
- Deployment today is Docker + nginx (`node:22.23.1-alpine` build → `nginx:1.27-alpine`; SPA
  `try_files`, 1 y immutable cache on `/assets/`, `no-cache` on `index.html`).
- **Only two `VITE_*` vars exist:** `VITE_GLIFIC_API_URL` → `API_BASE` (default `'/api'`) and
  `VITE_WEB_SOCKET` → `WEB_SOCKET` (default `'/web_socket'`). Both commented out; dev uses the Vite
  proxy. **No env var for org shortcode, tenant, theme, branding or feature flags.** One non-`VITE_`
  var: `GLIFIC_BACKEND_PORT` (default `4001`), read by `vite.config.ts` at dev-server startup.
- **Tenant selection is entirely server-side.** The client sends no org identifier anywhere — auth
  POSTs carry only `{phone}` / `{phone, otp}`, the socket carries only `{token}`. Per `BUNNYSHELL.md`
  the backend's `SubdomainPlug` resolves the org from the request host. **Implication: one deployed
  widget ⇒ one org.**
- Dev server runs on `host: "glific.test"` over HTTPS via `vite-plugin-mkcert`, because Phoenix
  `check_origin` rejected `localhost`; proxies `/api` and `/web_socket` to `https://localhost:${port}`.
- `bunnyshell.yaml` assembles 4 components (postgres 15, backend, widget, staff console), each from
  its own repo/branch `web-channel-prototype`.

## 6. Socket / API layer

```ts
// webChannelSocket.ts:114-123
const socket = new Socket(WEB_SOCKET, { params: { token } });
socket.connect();
const channel = socket.channel(`web_channel:${contactId}`, {});
```

Join resolves with `reply.messages` (oldest→newest); rejects on `error` or a join timeout.

| Push | Payload |
|---|---|
| `new_message` | `{ body }` |
| `new_media_message` | `{ type, url, content_type?, filename?, caption? }` |
| `new_location_message` | `{ latitude, longitude }` |
| `blocks_response` | `{ message_id, component, values, summary, context? }` |
| `load_more` | `{ offset }` |
| `update_name` | `{ name }` |

Handled: `new_message` (append), `contact_updated` (`{ name }` → header rename + persist).
`socket.onOpen/onError/onClose` map to `'connecting' | 'open' | 'reconnecting'`.

**Reconnect** relies entirely on the phoenix client's built-in auto-reconnect — **no custom backoff,
no re-sync or gap-fill after reconnect** (comment at `webChannelSocket.ts:112-113`). The failed-send
path (`Chat.tsx:220-222`) deliberately keeps the optimistic bubble and assumes the client queues it.

**Auth token** comes from `verify-otp` and is stored in **localStorage** under `web_channel_session` as
`{ token, contactId, name }` (`webChannelAuth.ts:6-17`). Read synchronously by route guards.
**No expiry or refresh handling.**

REST endpoints called (all in `src/config.ts`): `POST /v1/session/name`,
`POST /v1/web_channel/request-otp`, `POST /v1/web_channel/verify-otp`,
`POST /v1/web_channel/upload` (multipart, `Authorization: Bearer <token>`).

## 7. Onboarding / product tour

**None.** Grepping `src/` and `package.json` for `joyride`, `driver.js`, `intro.js`, `shepherd`,
`onboard`, `walkthrough`, `tour` returns no matches. No tour library, no first-run state, no coach
marks, no dismissible hints, no `localStorage` "seen" flag.

## 8. Testing

**Vitest 4.1.10**, jsdom, globals on, configured inline in `vite.config.ts`. Setup loads
`@testing-library/jest-dom/vitest` and stubs `ResizeObserver`.

| File | Tests |
|---|---|
| `src/App.test.tsx` | 4 (route guards) |
| `src/routes/Login.test.tsx` | 3 (axios mocked) |
| `src/routes/Chat.test.tsx` | 7 (auth + socket + recorder mocked) |
| `src/components/chat/MessageBubble.test.tsx` | 6 |
| `src/components/chat/InteractiveMessage.test.tsx` | 28 across 7 describes |
| `src/components/chat/EditName.test.tsx` | 5 |
| `src/hooks/useAudioRecorder.test.ts` | 4 |
| `src/services/webChannelSocket.test.ts` | 10 |

**No e2e whatsoever** — no Playwright, no Cypress, no `e2e/` directory. **No CI.**
`@vitest/coverage-v8` is installed and `test:coverage` exists, but no thresholds, no reporters, no
upload. No Storybook, no visual regression, no `jest-axe`. The `blocks/` built-ins have no dedicated
test files; `src/config.ts`, `src/lib/whatsapp.tsx` and `src/components/ui/*` have no direct tests.

## 9. Accessibility and i18n

**i18n: none.** No i18next/react-intl/lingui, no locales directory, no language switcher, no RTL
(`components.json` sets `"rtl": false`), no `dir` handling. **Every user-facing string is a hardcoded
English literal** — `'Type a message'`, `'Send OTP'`, `'Verify'`, `'Invalid OTP'`, `'Reconnecting…'`,
`'Logout'`, `'Download file'`, `'Location'`, `'Menu'`, `'Submit'`, `'Your answer'`, `'Answered'`,
`'Could not send your answer. Please try again.'`, `'That file is too large (max 15 MB).'`.
`index.html` hardcodes `lang="en"`. The one locale-aware thing is time formatting
(`Intl.DateTimeFormat(undefined, …)` — browser locale, but forced 24-hour).

Note this cuts against message *content* already being multilingual — flows send whatever language the
org authored, so today only the chrome is English-locked.

**a11y — present but shallow.** 14 `aria-label`s on icon-only buttons, `aria-pressed` on `BlockOption`,
`aria-hidden` on the required asterisk, `htmlFor`/`id` pairing on the three labelled inputs, `alt` on
images (`BlockImage` defaults to decorative `alt=""` with an authored `image_alt` override, documented
at `primitives.tsx:21-22`), `loading="lazy"`, focus-visible rings from tokens, Radix Dialog for the
list menu (focus trap + Escape free). **Missing:** no `aria-live` on the message list (new messages
are not announced), no landmark roles beyond raw `header`/`footer`, no skip link, no focus management
after send/receive, no reduced-motion handling, no contrast audit, no documented keyboard path for the
carousel's horizontal scroll, recording timer not announced.

## 10. Prototype markers a reader should know

1. **OTP is fake.** `src/config.ts:19` — *"prototype: server does not actually send an SMS"*; the
   login screen prints `Prototype: use 9999`. No rate limiting, no resend cooldown, no phone validation.
2. **Dark mode is dead code** (§4).
3. **13 sidebar/chart tokens** carried from the shadcn default, unused.
4. **The embeddable widget is not built.** README: *"Built as an SPA now, structured so it can later be
   packaged as an embeddable widget… with Shadow-DOM / scoped-Tailwind style isolation."* No widget
   bundle, no iframe host script, no shadow root, no Tailwind prefix.
5. **README is stale** — its Structure section predates `blocks/` and `hooks/`, and it says the dev
   proxy targets `http://localhost:4000` while `vite.config.ts` targets `https://localhost:4001`.
6. **`bunnyshell.yaml` carries `# CONFIRM` markers**, and `BUNNYSHELL.md`'s hostname table doesn't
   match the yaml's actual hostnames.
7. **No error boundary, no offline queue, no send-status indicator.** A failed text send silently keeps
   its optimistic bubble while a failed blocks answer *does* roll back and show an error — inconsistent.
8. **No session expiry handling** — the localStorage token is trusted until the socket join fails,
   surfacing only as a permanent "Reconnecting…" label.
9. `.claude/agent-memory/test-automator/` exists but is empty; there is no `CLAUDE.md` in this repo.
