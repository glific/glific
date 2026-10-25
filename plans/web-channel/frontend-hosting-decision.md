# Frontend Hosting Decision — Glific Web Channel

**Status:** Draft for review · **Scope:** where to host the static PWA frontend for the web channel

Comparison of **Vercel, Netlify, Google Cloud CDN, and Gigalixir** (plus **Cloudflare Pages** as an
off-list contender) for serving the web-channel's static React/Vite PWA to **10–50M users in India**.

> This doc supersedes the first-pass "100 TB worst-case" framing. Egress here is modelled on the
> realistic **10M-user, daily-weekday-deploy** case (see §3). The **Asset versioning** row is now
> primary-verified for all hosts against a **React + Vite** stack (see §5) — this changed the scores
> and the balanced ranking.

---

## 1. TL;DR — the call

> **Decision taken (phase 1): Vercel.** We go with Vercel first because it resolves most of the current
> Glific-frontend pain in one move (India edge, immutable/versioned deploys, preview deployments, fast
> deploys), and at MVP volume the egress premium is immaterial. Revisit **Google CDN** (cost at scale) or
> **Cloudflare Pages** (free egress) if egress grows into tens of TB/month. The balanced analysis below
> stands on its own merits and is why those two remain the phase-2 fallbacks.

**Google Cloud CDN is the balanced-ranking winner (3.77) and the scale-correct pick; Vercel (3.59) is
the better developer experience.** Cost stopped being the deciding axis once we modelled realistic
10M-user volumes (§3) — at a few TB/month the providers are within ~$200/month of each other. And after
primary verification (§5), **asset versioning stopped being a differentiator too**: on a **React + Vite**
stack, *no* host keeps old lazy-loaded chunks live on production for free, so it must be solved
app-side (a `vite:preloadError` reload guard) on whichever host you pick. That leaves the decision
**led by India-PoPs, previews, and deploy DX**.

- **Google Cloud CDN** — real India PoPs (Mumbai/Delhi/Chennai) + lowest egress at high volume, and —
  counter-intuitively — the **cleanest versioning story** (never-delete bucket keeps every old chunk
  resolving on production). Cost is that previews, wildcard TLS, and deploy glue are all DIY.
- **Vercel** — best managed DX + automatic PR previews (unifies away from Netlify). Its chunk-404
  reputation is **Next.js-specific**: on Vite, immutable-assets routing doesn't apply and Skew Protection
  (Pro+) needs manual `VERCEL_DEPLOYMENT_ID` wiring. Costliest egress, but immaterial at 10M scale.
- **Netlify** — great DX, but **two disqualifiers for this use case**: no India PoP on Free/Pro
  (Singapore-served) *and* atomic deploys **expire** old chunks on production (staff-confirmed, no flag).
- **Gigalixir** — status quo; keep it for the **backend**. It is a BEAM PaaS mis-used as a static host
  (no CDN, US/EU origin, slug-replace kills old chunks, ~10-min deploys).
- **Cloudflare Pages (off-list)** — free unlimited egress + India PoPs, **but** its production domain
  serves only the latest deployment, so old lazy-loaded chunks 404 (see §5). Worth adding *if* paired
  with an app-level reload guard or R2 asset retention.

---

## 2. Weighted decision matrix

Scores 1–5 per dimension. Weights reflect the stated priorities and sum to 100. Weighted total is /5.

| Parameter | Weight | Vercel | Netlify | Google CDN | Gigalixir |
|---|--:|:--:|:--:|:--:|:--:|
| **CDN edge in India** | 22 | **5** — Mumbai region + PoPs, all tiers | **2** — no India PoP on Free/Pro; Singapore-served | **5** — Mumbai/Delhi/Chennai PoPs | **1** — no CDN; US/EU origin |
| **Asset versioning** (keep old Vite chunks live on prod) | 20 | **3** — Skew Protection (Pro+, manual Vite wiring); immutable-assets is Next.js-only | **2** — atomic deploys **expire** old chunks on prod; no flag (staff-confirmed) | **4** — never-delete bucket keeps all old chunks live; DIY setup, bulletproof | **1** — slug replaces build → chunk 404s |
| **Cost at scale** (egress) | 22 | **1** — $0.15/GB; Hobby non-commercial + 100 GB cap | **2** — ~$0.13/GB via credits | **3** — tiered $0.11→$0.025/GB; no free tier | **4** — bandwidth free, ~$25/mo app, but no CDN |
| **Deploy previews** | 10 | **5** — automatic per-PR, all tiers | **5** — unlimited, all tiers | **2** — DIY per-branch bucket via CI | **2** — DIY GH Action; each = full app |
| **Deploy speed** | 8 | **5** — ~1–3 min; instant rollback | **5** — ~1–3 min; instant rollback | **4** — rsync in seconds; cache-invalidation lag | **1** — ~10-min slug build (inherent) |
| **PWA / static fit** | 5 | **5** — SW, headers, SPA rewrites native | **5** — `_headers` / `_redirects` native | **4** — works; SPA fallback is manual | **3** — via Plug; always-on process, awkward |
| **Custom domain / wildcard** (`web.<org>.glific.com`) | 8 | **4** — CNAME ok; wildcard needs Vercel NS | **4** — wildcard Pro+; blocks branch aliases | **3** — Cert Manager + DNS auth for wildcard | **3** — 100 domains; wildcard = support + BYO cert |
| **Observability** | 5 | **4** — Analytics/Speed Insights (paid) | **4** — built-in RUM; 30-day on Pro | **5** — Cloud Monitoring: cache-hit, egress, latency | **2** — BEAM observer — N/A for static |
| **Weighted total** | 100 | **3.59** — rank 2 | **2.95** — rank 3 | **3.77** — rank 1 | **2.07** — rank 4 |

**How to read the ranks:** Google CDN leads the balanced score on the strength of India PoPs + lowest
egress + the cleanest (if DIY) versioning. Vercel is a close second on DX and previews. The versioning
row is now primary-verified against a **Vite** stack (§5) — correcting it (Vercel 5→3, Netlify 5→2,
Google 3→4) is what moved Google ahead of Vercel and dropped Netlify to third. Cloudflare (off-table,
§5) matches Google on cost but shares the managed hosts' "old chunks 404 on prod" behavior.

**Score legend:** 5 strong · 4 good · 3 mixed/DIY · 2 weak · 1 blocker.

---

## 3. Egress model (10M users, ~1 deploy every weekday)

For hashed, immutable, service-worker-cached assets, egress is **not** `users × sessions`. It is two
terms: **cold loads** (first-ever / cache-evicted) + **update deltas** (returning users re-fetching only
the *changed* chunks on routes they open). Daily deploys inflate the update term; lazy loading shrinks it.

```
Update egress = MAU × (active days/mo ≈ versions picked up) × (changed brotli bytes re-fetched)
              = 6M MAU × 8 active days × 150 KB
              ≈ 7.2 TB/month

Cold loads    = 10M × ~2 cold loads/yr ÷ 12 × 800 KB  ≈ 1.3 TB/month
index + SW revalidation                               ≈ 0.2 TB/month
                                                      ------------------
Central estimate                                      ≈ 8.5 TB/month
```

Why 150 KB, not the full 800 KB, per update: **vendor chunks stay cached** (only re-hash on dependency
bumps, not routine app-code deploys), and **unvisited lazy routes are never fetched**.

### Sensitivity

| Scenario | Changed KB/pickup | Active days/mo | MAU | Egress/mo |
|---|--:|--:|--:|--:|
| Lean | 100 | 5 | 5M | **~3.5 TB** |
| Central | 150 | 8 | 6M | **~8.5 TB** |
| Heavy | 250 | 12 | 7M | **~20 TB** |

*(One-time onboarding spike ≈ 10M × 800 KB ≈ 8 TB, spread across the ramp.)*

---

## 4. Cost at realistic volumes

Monthly egress bill (list prices; verify + negotiate committed-egress at volume):

| Provider | ~4 TB | ~8.5 TB | ~20 TB | Basis |
|---|--:|--:|--:|---|
| **Cloudflare Pages** | **$0** | **$0** | **$0** | free unlimited egress |
| **Google Cloud CDN** | ~$450 | ~$960 | ~$1,900 | India tiers $0.110 → $0.025/GB |
| **Netlify** | ~$530 | ~$1,130 | ~$2,660 | ~$0.13/GB via credits |
| **Vercel** (Pro) | ~$465 | ~$1,160 | ~$2,920 | $0.15/GB after 1 TB |

**Takeaway:** at the central 10M estimate everything except Cloudflare lands ~$1k/month, within ~$200 of
each other. Cost is a **tie-breaker, not a gate**. The strongest cost lever is not the provider — it's
**changed-bytes-per-deploy** (keep a stable vendor chunk so daily deploys re-hash ~100 KB, not ~300 KB).

> ⚠️ **Media egress is the real cost story, and it's separate.** User voice-notes/images/files ride a
> different path (GCS-direct or backend), not the static host. A 500 KB image × millions of sends dwarfs
> the entire JS bundle. Budget that independently; it does not change the static-hosting choice.

---

## 5. Asset versioning across hosts — VERIFIED (React + Vite stack)

The requirement: after a deploy, a user with a tab open must still be able to lazy-load a content-hashed
chunk that the *previous* build emitted. "Immutable deployments retained at permalink URLs" does **not**
satisfy this — what matters is whether the **production/custom domain** serves superseded chunks.
Primary-verified per host below. **Headline: on a Vite stack, no host solves this for free.**

| Host | Old chunks live on prod? | Mechanism / why |
|---|---|---|
| **Google CDN** | **YES** (if you never delete) | Bucket serves whatever's in it; `rsync` without `-d` keeps every old hash. DIY but bulletproof. |
| **Vercel** | **NO for Vite** (by default) | Immutable-assets routing is **Next.js 16.3+ only**; Skew Protection (Pro+) pins clients but auto-supports Next/SvelteKit/Qwik/Astro/Nuxt — plain Vite needs manual `VERCEL_DEPLOYMENT_ID` wiring. |
| **Netlify** | **NO** | Atomic deploys **expire** old assets on the production alias; staff: *"there is no automatic method"* to keep them. Old deploys survive only at `*--<hash>.netlify.app` permalinks. |
| **Cloudflare Pages** | **NO** | Production serves only the latest deployment; missing chunk falls back to the SPA shell → **`200` HTML** where JS was expected. |
| **Gigalixir** | **NO** | Slug replaces the running release; old hashed URLs gone. (The current pain.) |

**Failure signature** (same class everywhere except Google-no-delete):
```
Failed to fetch dynamically imported module
'…' is not a valid JavaScript MIME type   # when the host returns the HTML shell with 200
```

**Sources:**
- Vercel: [Skew Protection](https://vercel.com/docs/skew-protection) (Pro+; default max-age 1 day,
  configurable up to retention policy) · [Immutable static assets](https://vercel.com/changelog/optimized-cdn-caching-and-deploying-of-immutable-static-assets)
  (Next.js 16.3+ only)
- Netlify: [Keep .js chunks from old deploys](https://answers.netlify.com/t/keep-js-chunks-from-old-deploys/5991)
  (staff confirmation) · [nuxt/nuxt#20950](https://github.com/nuxt/nuxt/issues/20950)
- Cloudflare: [Serving Pages](https://developers.cloudflare.com/pages/configuration/serving-pages/) ·
  [React lazy-load chunk errors on Pages (ard.ninja)](https://ard.ninja/blog/2026-05-16-react-lazy-vite-cloudflare-pages-stale-chunk-errors/)

### The fix is application-level and host-agnostic

Because no managed host solves this for Vite, treat versioning as an **app-level checkbox**, not a
provider feature. Ranked:

1. **`vite:preloadError` reload guard (recommended, universal):** Vite emits this event when a dynamic
   import fails; catch it → force one full-page reload → the user silently lands on the new version. A
   few lines; works on *every* host. **Ship this regardless of provider.**
2. **Retain old hashed assets:** never-delete bucket (GCS/R2) + a retention window (e.g. 30 days). On
   **Google CDN this is the native model**, which is why it scores highest here. Storage cost is trivial.
3. **Vercel Skew Protection (Pro+):** most "managed", but for Vite you must wire `VERCEL_DEPLOYMENT_ID`
   into asset requests yourself — so it's not zero-effort on this stack.

**Implication for the matrix:** with the reload guard shipped, this axis nearly equalizes — which
*removes* a reason to pay the Vercel/Netlify premium and pushes the decision toward India-PoPs + cost +
previews. It also means **Google CDN's DIY nature is an advantage here**, not a drawback.

---

## 6. Open items before committing

- [x] **Primary-verify Netlify's production behavior** — VERIFIED: old chunks **404 on production**
      (atomic deploys expire them; staff-confirmed, no flag). See §5.
- [x] **Confirm Vercel Skew Protection** — VERIFIED: **Pro+ only**, default max-age 1 day, configurable up
      to the deployment-retention policy; auto-supports Next/SvelteKit/Qwik/Astro/Nuxt but **not plain
      Vite** (needs manual `VERCEL_DEPLOYMENT_ID`); immutable-assets routing is **Next.js-only**. See §5.
- [ ] **Ship the app-level guard regardless of host** — the `vite:preloadError` reload handler; it is now
      the *primary* versioning mechanism on every provider (not a fallback), so it's non-optional.
- [ ] **Pin real numbers** — plug in the actual initial bundle size (brotli) and typical changed-KB per
      deploy to replace the 800 KB / 150 KB placeholders.
- [ ] **Budget media egress separately** — the user-generated media path, not the static bundle.
- [ ] **Wildcard TLS plan** for `web.<org>.glific.com` per chosen host (Vercel NS vs Netlify Pro vs GCP
      Certificate Manager).

---

## Appendix — weighting rationale

| Dimension | Weight | Why |
|---|--:|---|
| CDN edge in India | 22 | Core problem: slow first-load for Indian users on the US-origin status quo |
| Cost at scale | 22 | 10–50M-user audience; egress is the dominant variable cost |
| Asset versioning | 20 | Lazy-load chunk 404s are a live production failure today |
| Deploy previews | 10 | Currently on Netlify; goal is to unify onto one platform |
| Deploy speed | 8 | ~10-min Gigalixir deploys are a felt pain |
| Custom domain / wildcard | 8 | `web.<org>.glific.com` per-org, multi-tenant |
| PWA / static fit | 5 | Table stakes; all four support it to some degree |
| Observability | 5 | Nice-to-have; basic app health |

*Cost basis: 2026 list prices from official docs. At this volume, pursue committed-egress / Enterprise
pricing. Estimates assume a high CDN cache-hit ratio; cache-fill misses add ~$0.01/GB.*
