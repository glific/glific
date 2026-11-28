#!/usr/bin/env bash
# Runs as a buildpack hook. The buildpack echoes hook commands after expanding them,
# so the credentials are read here instead of in elixir_buildpack.config.
set -euo pipefail

mix hex.repo add oban https://getoban.pro/repo \
  --fetch-public-key "${OBAN_KEY_FINGERPRINT}" \
  --auth-key "${OBAN_KEY}"
