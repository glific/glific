import http from 'k6/http';
import { check } from 'k6';
import { Counter, Trend } from 'k6/metrics';

// Reproduces the URL-scan traffic seen in production and measures what each request costs us.
//
// Two scenarios run back to back, never at the same time, so CPU sampled by
// sample_resources.sh can be attributed to one or the other.
//
//   known_host    /.env and friends on a host that resolves to a real organization.
//                 The org is cached after the first request on every branch, so this is the
//                 control: it should look the same before and after the fix.
//
//   unknown_host  the same paths with a Host that resolves to nothing, rotated per request.
//                 A miss is never cached, so before the fix each request costs a database
//                 query and a raised exception. This is the scenario the fix is about.
//
// Both scenarios use paths that match no route, so both are charged the RATE_LIMIT_API_GLOBAL
// budget and a run should be mostly 429 once the first minute's allowance is spent. Raise that
// limit if you want to measure what the work costs rather than what refusing it costs.

const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';
const RATE = Number(__ENV.RATE || 200);
const DURATION_S = Number(__ENV.DURATION_S || 60);
const GAP_S = Number(__ENV.GAP_S || 10);
const LABEL = __ENV.LABEL || 'run';
const SCENARIO = __ENV.SCENARIO || 'both';
const HOST_SUFFIX = __ENV.HOST_SUFFIX || 'glific.test';

const SCAN_PATHS = [
  '/.env',
  '/aws.env',
  '/.aws/credentials',
  '/.git/config',
  '/wp-login.php',
  '/phpmyadmin/index.php',
  '/config.json',
  '/vendor/.env',
];

const status404 = new Counter('scan_status_404');
const status403 = new Counter('scan_status_403');
const status429 = new Counter('scan_status_429');
const statusOther = new Counter('scan_status_other');

const knownHostDuration = new Trend('scan_known_host_duration', true);
const unknownHostDuration = new Trend('scan_unknown_host_duration', true);

function arrivalRate(exec, startTime) {
  return {
    executor: 'constant-arrival-rate',
    rate: RATE,
    timeUnit: '1s',
    duration: `${DURATION_S}s`,
    // Headroom for the slow branch: on master an unknown host blocks on a query per request.
    preAllocatedVUs: Math.max(50, Math.ceil(RATE / 2)),
    maxVUs: Math.max(200, RATE * 2),
    exec,
    startTime,
    tags: { scan_scenario: exec },
  };
}

function scenarios() {
  const known = arrivalRate('knownHost', '0s');
  const unknown = arrivalRate('unknownHost', `${DURATION_S + GAP_S}s`);

  if (SCENARIO === 'known_host') return { knownHost: known };
  if (SCENARIO === 'unknown_host') return { unknownHost: arrivalRate('unknownHost', '0s') };
  return { knownHost: known, unknownHost: unknown };
}

export const options = {
  scenarios: scenarios(),
  // The point of the run is to measure a slow branch, not to fail on it.
  thresholds: {},
  summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
};

function scanPath() {
  return SCAN_PATHS[Math.floor(Math.random() * SCAN_PATHS.length)];
}

function record(res, trend) {
  trend.add(res.timings.duration);

  if (res.status === 404) status404.add(1);
  else if (res.status === 403) status403.add(1);
  else if (res.status === 429) status429.add(1);
  else statusOther.add(1);

  // 429 is the expected answer once the allowance is spent, so it is not a failed check. What
  // would be a failure is the server falling over, or answering something nobody predicted.
  check(res, {
    'answered without a server error': (r) => r.status > 0 && r.status < 500,
    'answered with a status the limiter or router should produce': (r) =>
      [404, 403, 429].includes(r.status),
  });
}

export function knownHost() {
  const res = http.get(`${BASE_URL}${scanPath()}`, { tags: { scan_scenario: 'known_host' } });
  record(res, knownHostDuration);
}

export function unknownHost() {
  // Rotated per request: a repeated host would be cached by the fix and hide the difference.
  const host = `scan-${__VU}-${__ITER}.${HOST_SUFFIX}`;

  const res = http.get(`${BASE_URL}${scanPath()}`, {
    headers: { Host: host },
    tags: { scan_scenario: 'unknown_host' },
  });

  record(res, unknownHostDuration);
}

function count(data, metric) {
  const values = data.metrics[metric] && data.metrics[metric].values;
  return values ? values.count || 0 : 0;
}

// A Trend's values carry no `count`, unlike a Counter's, so presence is judged on `med`.
function trend(data, metric) {
  const values = data.metrics[metric] && data.metrics[metric].values;
  if (!values || values.med === undefined) return 'not run';
  return [
    `med=${values.med.toFixed(2).padStart(8)}ms`,
    `p95=${values['p(95)'].toFixed(2).padStart(8)}ms`,
    `p99=${values['p(99)'].toFixed(2).padStart(8)}ms`,
    `max=${values.max.toFixed(2).padStart(8)}ms`,
  ].join('  ');
}

export function handleSummary(data) {
  const lines = [
    '',
    `URL scan load test — ${LABEL}`,
    `  target        ${BASE_URL}`,
    `  arrival rate  ${RATE}/s for ${DURATION_S}s per scenario`,
    '',
    `  known host    ${trend(data, 'scan_known_host_duration')}`,
    `  unknown host  ${trend(data, 'scan_unknown_host_duration')}`,
    '',
    `  responses     404=${count(data, 'scan_status_404')}  403=${count(data, 'scan_status_403')}  429=${count(data, 'scan_status_429')}  other=${count(data, 'scan_status_other')}`,
    '',
    count(data, 'scan_status_429') === 0
      ? '  No 429s. Either nothing rate limits unmatched paths, or the limit was raised for this run.'
      : '  Saw 429s: unmatched paths are rate limited, as expected with RATE_LIMIT_API_GLOBAL set.',
    '',
  ];

  return {
    stdout: lines.join('\n'),
    [`k6/results/${LABEL}.json`]: JSON.stringify(data, null, 2),
  };
}
