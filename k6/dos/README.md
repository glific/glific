# Denial of service

Floods Glific with unauthenticated requests and measures what each one costs. Written against the
URL-scan traffic seen in production (`GET /aws.env`, `/.env`, `/.git/config`, …), but the shape
applies to any flood of cheap unauthenticated requests.

See `../README.md` for installing k6, the shared resource sampler, and the two measurement
pitfalls (code reloading, idle baselines) that will otherwise ruin the numbers.

## Scenarios

Two run back to back, never at once, so sampled CPU can be attributed to one of them.

| Scenario | Request | Why |
|---|---|---|
| `known_host` | scan paths on the default host | Control. The organization is cached after the first request, so this should not move between branches. |
| `unknown_host` | same paths, `Host` rotated per request | The organization lookup misses. Before `Glific.Partners.OrganizationIndex` a miss was never cached, so each request cost a query. |

The `Host` rotation is the point. A fixed host is cached after one request, so a test that only
varies the path measures nothing.

## Reading the output

`scan_status_429` is the headline. `GlificWeb.RateLimitPlug` in `:global` mode caps requests that
match no route at `RATE_LIMIT_GLOBAL` per minute per address, so a run should be almost entirely
429 once the first minute's allowance is spent. Before that limit existed it was zero however hard
the test pushed, because the `:api` pipeline never sees a request that matches no route.

Raise `RATE_LIMIT_GLOBAL` if you want to measure the cost of the work itself rather than the cost
of rejecting it — with the limit active almost nothing reaches the router, which is the point, but
it also stops the run exercising tenant resolution.

The transaction delta from the sampler is the number to trust. CPU percentages move with whatever
else the machine is doing, and latency on the `known_host` path is dominated by Phoenix's 404
error rendering rather than by anything being measured.

## Knobs

| Variable | Default | Meaning |
|---|---|---|
| `BASE_URL` | `http://localhost:4000` | Target. Use the http port; https is 4001. |
| `RATE` | `200` | Requests per second, per scenario. |
| `DURATION_S` | `60` | Seconds per scenario. |
| `GAP_S` | `10` | Idle gap between scenarios, so CPU can be attributed. |
| `SCENARIO` | `both` | `known_host` or `unknown_host` to run just one. |
| `HOST_SUFFIX` | `glific.test` | Domain the rotated hosts are built under. |
| `LABEL` | `run` | Names the output files. |

## Reference numbers

Measured locally at 200 rps for 30s per scenario, 12,000 requests, with `code_reloader: false`,
comparing `edaba1029` against the branch that added the index and the global limit:

| | before | after |
|---|---|---|
| 429s | 0 | 11,881 |
| database transactions | 6,578 | 565 |
| BEAM CPU avg | 39.4% | 14.4% |
| BEAM CPU peak | 93.0% | 37.2% |
| Postgres CPU avg | 1.2% | 0.2% |

Idle is around 575 transactions for the same 80s window, so 6,578 against 6,001 unknown-host
requests is one transaction per request, and 565 is indistinguishable from doing nothing.
