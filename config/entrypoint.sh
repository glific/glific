#!/bin/sh
# Prepare the database and start the server.
#
# The app is precompiled into the image (see Dockerfile: COPY . . + mix compile);
# the `mix compile` below is a fast no-op safety net. On the first successful boot
# of a container we build the schema from migrations and seed the demo org.
#
# structure.sql load is intentionally NOT used: on this branch it is inconsistent
# with the Oban Pro migrations (ships the oban_producers DDL but not the matching
# schema_migrations rows), so `ecto.load` + `ecto.migrate` cannot both succeed.
set -e

MARKER="/app/glific/priv/cert/GLIFIC_FIRST_STARTUP"

mix compile

if [ ! -e "$MARKER" ]; then
    mix ecto.drop --force --force-drop
    mix ecto.create
    mix ecto.migrate
    mix phil_columns.seed --tenant glific
    mix run priv/repo/seeds_dev.exs
    mix run priv/repo/seeds_credentials.exs
    # Touch only after success: a failed first boot retries the full reset instead
    # of getting stuck on a half-migrated database.
    touch "$MARKER"
else
    mix ecto.migrate
fi

mix phx.server
