#!/bin/sh
# Prepare the database and start the server.
#
# The app is precompiled into the image (see Dockerfile: COPY . . + mix compile),
# so `mix compile` here is a fast no-op safety net.
#
# A *fresh* database is set up from structure.sql via `mix ecto.reset` (drop + create + load +
# migrate + seed). On every later boot we only migrate, so data on the persistent Postgres
# volume survives redeploys.
#
# CRITICAL: the "is this a fresh database?" check reads the DATABASE ITSELF (which lives on the
# persistent volume), never a marker file on the container filesystem. A container-local marker
# is recreated on every redeploy, so each boot would look like a first boot and `ecto.reset`
# would wipe the data even though the Postgres volume persisted it.
set -e

mix compile

# DATABASE_URL is set by the deploy environment (Bunnyshell) and is also required by
# config/runtime.exs, so the mix commands below need it regardless — fail fast if it's missing.
if [ -z "$DATABASE_URL" ]; then
    echo "DATABASE_URL is not set" >&2
    exit 1
fi

# psql needs a libpq URI; our DATABASE_URL uses the ecto:// scheme.
PG_URL=$(printf '%s' "$DATABASE_URL" | sed 's|^ecto://|postgresql://|')

# Wait for Postgres to accept connections before deciding anything. Bunnyshell may start the
# backend before the db is ready; without this, a transient connection failure would look like
# an empty database and trigger a destructive ecto.reset.
i=0
until psql "$PG_URL" -c '\q' 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 30 ]; then
        echo "database not reachable after 60s" >&2
        exit 1
    fi
    echo "waiting for database... ($i)"
    sleep 2
done

# The DB is reachable. Treat it as already set up if the seeded `organizations` table exists and
# has a row; a fresh DB errors on the missing relation and yields an empty string -> full reset.
SEEDED=$(psql "$PG_URL" -tAc "SELECT EXISTS (SELECT 1 FROM organizations LIMIT 1)" 2>/dev/null || echo "")

if [ "$SEEDED" = "t" ]; then
    mix ecto.migrate
else
    mix ecto.reset
fi

# Start as a named, distributed node so you can attach a remote console to THIS running
# instance (no second app, no port clash, no duplicate Oban):
#   iex --sname console --remsh "glific@$(hostname -s)"
# No --cookie is passed: the VM auto-reads/creates ~/.erlang.cookie, and the console (same user,
# same container) reads the same file, so the cookies match automatically.
# `exec` replaces this shell with the BEAM so SIGTERM reaches the VM for graceful shutdown.
exec elixir --sname glific -S mix phx.server
