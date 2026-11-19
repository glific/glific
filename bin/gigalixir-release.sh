#!/usr/bin/env bash
#
# gigalixir-release.sh - drive a version bump, GitHub release and deploy.
#
# Replaces the manual production release checklist. Stops at two confirmations
# (bump, deploy) and refuses to continue when the repo is not in a clean,
# up-to-date state. The bump commit is pushed to master by the bump-version
# workflow (a GitHub App on the ruleset bypass list), so no admin rights are
# needed. Ends by handing off to gigalixir-verify-deploy.sh, so the release is
# not "done" until the app has held the new version for five minutes.
#
# Works in both glific (mix.exs) and glific-frontend (package.json).
#
# Usage
#   bin/gigalixir-release.sh --env staging --dry-run    # walk it, execute nothing
#   bin/gigalixir-release.sh --env staging
#   bin/gigalixir-release.sh --env production
#
# Note on staging: merging to master already triggers a CI deploy to staging, so
# --env staging is for testing this script, not a normal path. Production is the
# manual target this exists for.

set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERIFIER="${SCRIPT_DIR}/gigalixir-verify-deploy.sh"

# env|app name|git remote  (must stay in sync with gigalixir-verify-deploy.sh)
readonly TARGETS="
staging|glific-staging|staging
frontend-staging|glific-frontend-staging|gigalixir
production|glific|production
"

ENV_NAME="" APP="" REMOTE="" NEW_VERSION="" BUMP="" RELEASE_TITLE=""
BASE_BRANCH="master" DRY_RUN=0 ASSUME_YES=0
SKIP_RELEASE=0 SKIP_VERIFY=0
STABLE_WINDOW=300
BUMP_TIMEOUT=600
readonly BUMP_WORKFLOW="bump-version.yml"

CURRENT_VERSION="" VERSION_FILE="" VERSION_PATTERN="" PROJECT_KIND=""
DEPLOY_SHA=""
DISCORD_WEBHOOK=""

usage() { sed -n '2,21p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'; }

die() {
  printf '\n%s\n' "error: $*" >&2
  exit 1
}

log()  { printf '  %s\n' "$*"; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# Every mutating command goes through run(), so --dry-run is total rather than
# a promise sprinkled through the script.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  [dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

confirm() {
  local prompt="$1"
  if [ "$ASSUME_YES" -eq 1 ]; then
    log "auto-confirmed: ${prompt}"
    return 0
  fi
  [ -t 0 ] || die "not a terminal and --yes not given; refusing to guess at '${prompt}'"
  local reply=""
  printf '\n%s [y/N]: ' "$prompt"
  read -r reply
  case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

abort() {
  printf '\nAborted%s.\n' "${1:+ - $1}"
  exit 1
}

# A value-taking flag passed as the last token leaves no $2 to consume; `shift 2`
# would then fail silently and the while-loop would spin on the same flag forever.
# need "$@" asserts a value follows before we shift past it.
need() { [ "$#" -ge 2 ] || die "missing value for $1"; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --env) need "$@"; ENV_NAME="$2"; shift 2 ;;
      --app) need "$@"; APP="$2"; shift 2 ;;
      --remote) need "$@"; REMOTE="$2"; shift 2 ;;
      --version) need "$@"; NEW_VERSION="$2"; shift 2 ;;
      --bump) need "$@"; BUMP="$2"; shift 2 ;;
      --title) need "$@"; RELEASE_TITLE="$2"; shift 2 ;;
      --base) need "$@"; BASE_BRANCH="$2"; shift 2 ;;
      --stable-window) need "$@"; STABLE_WINDOW="$2"; shift 2 ;;
      --discord-webhook) need "$@"; DISCORD_WEBHOOK="$2"; shift 2 ;;
      --skip-release) SKIP_RELEASE=1; shift ;;
      --skip-verify) SKIP_VERIFY=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --yes) ASSUME_YES=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
  done

  [ -n "$ENV_NAME" ] || [ -n "$APP" ] || die "--env is required (staging | frontend-staging | production)"

  if [ -n "$ENV_NAME" ]; then
    local row
    row=$(printf '%s' "$TARGETS" | grep "^${ENV_NAME}|") || die "unknown --env '$ENV_NAME'"
    [ -n "$APP" ] || APP=$(printf '%s' "$row" | cut -d'|' -f2)
    [ -n "$REMOTE" ] || REMOTE=$(printf '%s' "$row" | cut -d'|' -f3)
  fi
  [ -n "$REMOTE" ] || die "--remote could not be resolved; pass it explicitly"
}

read_version() { grep -m1 -E "$VERSION_PATTERN" | sed -E 's/.*"([^"]+)".*/\1/'; }

detect_project() {
  if [ -f mix.exs ]; then
    PROJECT_KIND="elixir"
    VERSION_FILE="mix.exs"
    VERSION_PATTERN='^\s*version: *"[0-9]'
  elif [ -f package.json ]; then
    PROJECT_KIND="node"
    VERSION_FILE="package.json"
    VERSION_PATTERN='^\s*"version": *"[0-9]'
  else
    die "no mix.exs or package.json here - run this from the repo root"
  fi
  CURRENT_VERSION=$(read_version <"$VERSION_FILE")

  [[ "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] \
    || die "could not read a semver out of ${VERSION_FILE} (got '${CURRENT_VERSION}')"
}

preflight() {
  step "Preflight"

  local missing=""
  for c in git gh jq curl gigalixir; do
    command -v "$c" >/dev/null 2>&1 || missing="${missing} ${c}"
  done
  [ -z "$missing" ] || die "missing required commands:${missing}"

  git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"
  [ -x "$VERIFIER" ] || die "verifier not found or not executable: ${VERIFIER} (chmod +x it)"

  gh auth status >/dev/null 2>&1 || die "gh is not authenticated - run: gh auth login"
  gigalixir account >/dev/null 2>&1 || die "gigalixir is not authenticated - run: gigalixir login"
  git remote get-url "$REMOTE" >/dev/null 2>&1 || die "git remote '${REMOTE}' does not exist"

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)
  [ "$branch" = "$BASE_BRANCH" ] || die "on branch '${branch}', expected '${BASE_BRANCH}'"

  [ -z "$(git status --porcelain)" ] || die "working tree is dirty - commit or stash first"

  log "fetching origin"
  git fetch --quiet origin "$BASE_BRANCH" || die "git fetch failed"

  local local_sha remote_sha
  local_sha=$(git rev-parse HEAD)
  remote_sha=$(git rev-parse "origin/${BASE_BRANCH}")
  [ "$local_sha" = "$remote_sha" ] \
    || die "local ${BASE_BRANCH} (${local_sha:0:7}) differs from origin/${BASE_BRANCH} (${remote_sha:0:7}) - pull or push first"

  log "on ${BASE_BRANCH}, clean, in sync with origin (${local_sha:0:7})"
  log "project: ${PROJECT_KIND} (${VERSION_FILE}), current version ${CURRENT_VERSION}"
  log "target: app ${APP} via remote ${REMOTE}"
  log "$(git remote get-url "$REMOTE")"
}

next_version() {
  local part="$1" base="${CURRENT_VERSION%%-*}"
  local major minor patch
  IFS='.' read -r major minor patch <<<"$base"
  case "$part" in
    major) printf '%d.0.0' "$((major + 1))" ;;
    minor) printf '%d.%d.0' "$major" "$((minor + 1))" ;;
    patch) printf '%d.%d.%d' "$major" "$minor" "$((patch + 1))" ;;
    *) die "invalid bump '${part}' (use patch, minor or major)" ;;
  esac
}

choose_version() {
  step "Version"

  [ -n "$BUMP" ] && NEW_VERSION=$(next_version "$BUMP")

  if [ -z "$NEW_VERSION" ]; then
    [ -t 0 ] || die "no --version or --bump given and stdin is not a terminal"
    local p n mj reply
    p=$(next_version patch); n=$(next_version minor); mj=$(next_version major)
    printf '  Current version: %s   (%s)\n' "$CURRENT_VERSION" "$VERSION_FILE"
    printf '    1) patch -> %s\n    2) minor -> %s\n    3) major -> %s\n' "$p" "$n" "$mj"
    printf '  Choose [1-3, or type an exact version]: '
    read -r reply
    case "$reply" in
      1) NEW_VERSION="$p" ;;
      2) NEW_VERSION="$n" ;;
      3) NEW_VERSION="$mj" ;;
      "") abort "no version chosen" ;;
      *) NEW_VERSION="$reply" ;;
    esac
  fi

  [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || die "'${NEW_VERSION}' is not a valid semver"
  [ "$NEW_VERSION" != "$CURRENT_VERSION" ] || die "new version equals current version (${CURRENT_VERSION})"

  git rev-parse -q --verify "refs/tags/v${NEW_VERSION}" >/dev/null \
    && die "tag v${NEW_VERSION} already exists locally"
}

trigger_bump() {
  step "Version bump"

  cat <<EOF

  -- About to do -----------------------------------
   trigger  ${BUMP_WORKFLOW} on ${BASE_BRANCH}
   change   ${VERSION_FILE}  ${CURRENT_VERSION} -> ${NEW_VERSION}
   commit   pushed to ${BASE_BRANCH} by the release bot
  --------------------------------------------------
EOF
  confirm "Bump ${BASE_BRANCH} to ${NEW_VERSION}?" || abort "declined at the bump step"

  run gh workflow run "$BUMP_WORKFLOW" --ref "$BASE_BRANCH" -f version="$NEW_VERSION" \
    || die "could not trigger the ${BUMP_WORKFLOW} workflow"
}

wait_for_bump() {
  step "Wait for bump"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] wait for origin/${BASE_BRANCH} to reach ${NEW_VERSION}"
    DEPLOY_SHA=$(git rev-parse HEAD)
    return 0
  fi

  log "waiting up to ${BUMP_TIMEOUT}s for origin/${BASE_BRANCH} to reach ${NEW_VERSION}"
  local deadline=$((SECONDS + BUMP_TIMEOUT))
  until git fetch --quiet origin "$BASE_BRANCH" \
        && [ "$(git show "origin/${BASE_BRANCH}:${VERSION_FILE}" | read_version)" = "$NEW_VERSION" ]; do
    [ "$SECONDS" -lt "$deadline" ] \
      || die "${BASE_BRANCH} not bumped after ${BUMP_TIMEOUT}s - check the ${BUMP_WORKFLOW} workflow run"
    sleep 10
  done

  git pull --ff-only origin "$BASE_BRANCH" || die "git pull failed"
  DEPLOY_SHA=$(git rev-parse HEAD)
  log "bumped; ${BASE_BRANCH} is now at ${DEPLOY_SHA:0:7}"
}

create_release() {
  [ "$SKIP_RELEASE" -eq 1 ] && { log "skipping GitHub release (--skip-release)"; return 0; }

  step "GitHub release"

  local tag="v${NEW_VERSION}"
  if [ -z "$RELEASE_TITLE" ]; then
    if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
      RELEASE_TITLE="$tag"
    else
      printf '  Release title [%s]: ' "$tag"
      read -r RELEASE_TITLE
      [ -n "$RELEASE_TITLE" ] || RELEASE_TITLE="$tag"
    fi
  fi

  log "tag ${tag} on ${BASE_BRANCH} (${DEPLOY_SHA:0:7}), title \"${RELEASE_TITLE}\""

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] gh release create ${tag} --target ${BASE_BRANCH} --title '${RELEASE_TITLE}' --generate-notes"
    return 0
  fi

  gh release create "$tag" --target "$BASE_BRANCH" --title "$RELEASE_TITLE" --generate-notes \
    || die "gh release create failed (${BASE_BRANCH} is already bumped - create the release manually, then deploy)"

  log "released ${tag}"
}

deploy() {
  step "Deploy"

  cat <<EOF

  -- About to DEPLOY -------------------------------
   app      ${APP}
   remote   ${REMOTE}  ($(git remote get-url "$REMOTE"))
   sha      ${DEPLOY_SHA:0:7}
   version  ${NEW_VERSION}
  --------------------------------------------------
EOF

  # Production gets a typed confirmation rather than a single keystroke.
  if [ "$ENV_NAME" = "production" ] && [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    local typed=""
    printf '\n  This deploys to PRODUCTION. Type the app name (%s) to continue: ' "$APP"
    read -r typed
    [ "$typed" = "$APP" ] || abort "app name did not match"
  else
    confirm "Deploy ${NEW_VERSION} to ${APP}?" || abort "declined at the deploy step"
  fi

  log "pushing to ${REMOTE} - the Gigalixir build output follows, this takes a few minutes"
  run git push "$REMOTE" "${BASE_BRANCH}:master" || die "git push to ${REMOTE} failed - nothing was deployed"
}

verify() {
  [ "$SKIP_VERIFY" -eq 1 ] && { log "skipping verification (--skip-verify)"; return 0; }

  step "Verify"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] ${VERIFIER} --app ${APP} --sha ${DEPLOY_SHA:0:7} --app-version ${NEW_VERSION}"
    return 0
  fi

  # Scope the webhook to just this subprocess via an inline assignment, so git/gh (and
  # anything they spawn) never inherit it. With no --discord-webhook, fall through to
  # whatever DISCORD_WEBHOOK_URL is already in the environment.
  local vargs=(--app "$APP" --sha "$DEPLOY_SHA" --app-version "$NEW_VERSION" --stable-window "$STABLE_WINDOW")
  if [ -n "$DISCORD_WEBHOOK" ]; then
    DISCORD_WEBHOOK_URL="$DISCORD_WEBHOOK" "$VERIFIER" "${vargs[@]}"
  else
    "$VERIFIER" "${vargs[@]}"
  fi
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    cat <<EOF

  ==================================================
   DEPLOYMENT FAILED - ${APP} did not stay healthy on ${NEW_VERSION}
  ==================================================
   logs      gigalixir logs -a ${APP}
   pods      gigalixir ps -a ${APP}
   releases  gigalixir releases -a ${APP}
   rollback  gigalixir releases:rollback -a ${APP}

   The GitHub release v${NEW_VERSION} exists and master is bumped;
   only the deploy is bad. Roll back, then investigate.
EOF
    exit "$rc"
  fi

  cat <<EOF

  ==================================================
   RELEASE COMPLETE - ${APP} is live on ${NEW_VERSION} (${DEPLOY_SHA:0:7})
  ==================================================
EOF
}

main() {
  parse_args "$@"
  detect_project
  [ "$DRY_RUN" -eq 1 ] && printf '\n*** DRY RUN - nothing will be changed, pushed or deployed ***\n'
  preflight

  # Only production is a versioned release (bump -> GitHub release).
  # staging / frontend-staging just deploy the current master and verify - no ceremony.
  if [ "$ENV_NAME" = "production" ]; then
    choose_version
    trigger_bump
    wait_for_bump
    create_release
  else
    DEPLOY_SHA=$(git rev-parse HEAD)
    NEW_VERSION="$CURRENT_VERSION"
    step "Version"
    log "no bump for ${ENV_NAME} - deploying current ${BASE_BRANCH} (${DEPLOY_SHA:0:7}) as ${CURRENT_VERSION}"
  fi

  deploy
  verify
}

main "$@"
