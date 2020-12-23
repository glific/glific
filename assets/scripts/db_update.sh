#!/bin/bash

# for production data run <GLIFIC_PATH>/assets/scripts/db_update.sh prod <DB_ENDPOINT>
# for seed data run <GLIFIC_PATH>/assets/scripts/db_update.sh

if [[ $1 == prod ]]
then

  # get production db
  pg_dump $2 -f glific.sql

  # import production db 
  dropdb glific_dev
  createdb -T template0 glific_dev
  psql glific_dev < glific.sql

  # run migrations and seed
  mix ecto.migrate
  mix phil_columns.seed --tenant glific

  # encrypt db
  mix run ./assets/scripts/db_encrypt.exs

  # remove production db file
  rm glific.sql

else 

  # reset db with seed_dev
  mix ecto.reset

fi