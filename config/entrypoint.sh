#!/bin/sh
# Prepare the database and start the server.
#
# The app is precompiled into the image (see Dockerfile: COPY . . + mix compile),
# so `mix compile` here is a fast no-op safety net.
#
# First boot of a container resets the schema from structure.sql via `mix ecto.reset`
# (drop + create + load + migrate + seed) — the drop is important: it clears any stale
# schema_migrations left on the persistent volume, otherwise `ecto.load --skip-if-loaded`
# silently skips loading structure.sql. Restarts only migrate, so demo data survives.
set -e

MARKER="/app/glific/priv/cert/GLIFIC_FIRST_STARTUP"

mix compile

if [ ! -e "$MARKER" ]; then
    mix ecto.reset
    # Touch only after success so a failed first boot retries the full reset
    # instead of getting stuck on a half-set-up database.
    touch "$MARKER"
else
    mix ecto.migrate
fi

mix phx.server
