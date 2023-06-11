#!/bin/sh
# This script checks if the container is started for the first time.
# It initializes the DB and then runs the server

ROOT="/app/glific/priv/cert"
GLIFIC_FIRST_STARTUP="$ROOT/GLIFIC_FIRST_STARTUP"
if [ ! -e /$GLIFIC_FIRST_STARTUP ]; then
    touch /$GLIFIC_FIRST_STARTUP
    # lets set things up
    mix setup
fi

mix phx.server