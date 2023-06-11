#!/bin/sh
# This script checks if the container is started for the first time.
# It initializes the DB and then runs the server

GLIFIC_FIRST_STARTUP="GLIFIC_FIRST_STARTUP"
if [ ! -e /$CONTAINER_FIRST_STARTUP ]; then
    touch /$CONTAINER_FIRST_STARTUP
    # lets set things up
    mix setup
fi

mix phx.server