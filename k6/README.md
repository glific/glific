# Load tests

[k6](https://k6.io) load tests for Glific, one directory per kind of test.

## Installing k6

```bash
brew install k6          # macOS
k6 version               # verify
```

k6 is a single Go binary with no runtime or services of its own. Other platforms are covered at
<https://grafana.com/docs/k6/latest/set-up/install-k6/>.

## Layout

```
k6/
├── README.md              this file — layout and install
├── sample_resources.sh    shared: samples BEAM CPU, Postgres CPU and database transactions
├── results/               output, git-ignored
└── dos/                   one directory per kind of test
    ├── README.md          what this test covers and how to read it
    └── dos_test.js
```

Each subdirectory is one kind of load test, holding its script and a README explaining what it
exercises, what to expect and how to interpret the output. Add a new kind by creating a sibling
directory rather than adding scenarios to an existing script — the scripts stay readable and the
resource sampler is shared.

| Directory | Covers |
|---|---|
| `dos/` | Denial of service: flooding unauthenticated requests, including paths that match no route |

## Running any test

Start a local Glific server, then run the sampler alongside the script:

```bash
k6/sample_resources.sh <label> 80 &        # BEAM/Postgres CPU + transaction delta
k6 run -e LABEL=<label> k6/dos/dos_test.js
```

Results land in `k6/results/` as `<label>.json` (k6) and `<label>-resources.csv` (sampler). The
sampler takes `PORT` (default `4000`) and `DB_NAME` (default `glific_dev`).

**Disable code reloading before measuring anything.** `config/dev.exs` sets `code_reloader: true`,
which puts `Phoenix.Ecto.CheckRepoStatus` in the endpoint ahead of everything else; it issues
roughly two database queries per request no matter what the application does, so a request
rejected at the edge still shows up as database work. Measured on this repo: the same 2,000
rejected requests cost 4,151 transactions with reloading on and 170 with it off, and median
latency went from 140ms to 0.45ms. Production does not run it. Set `code_reloader: false` for the
duration of a run and put it back afterwards.

**Take an idle sample on a settled server.** A genuinely idle Glific does a few hundred
transactions per 80 seconds, almost all connection-pool pings. For a minute or two after a load
run it is still draining Oban jobs and reads more than twenty times higher, which will swamp any
comparison.
