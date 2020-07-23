#!/bin/bash
# It is getting called from Dockerfile
# it is used to check if database connection is established,
# run the migrations
# starts the application.

# assign a default for the database_user / role
DB_ROLE=${POSTGRES_ROLE:-postgres}
DB_HOST=${DATABASE_HOST:-db}

# wait until Postgres is ready
while ! pg_isready -q -h $DB_HOST -p 5432 -U $DB_ROLE
do
  echo "$(date) - waiting for database to start $DB_HOST, $DB_ROLE"
  sleep 2
done

echo "connected"

bin="/app/bin/prod"
eval "$bin eval \"Glific.Release.migrate\""
# start the elixir application
exec "$bin" "start"
