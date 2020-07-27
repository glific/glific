# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds_scale.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Glific.Repo.insert!(%Glific.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Glific.Seeds.SeedsScale

SeedsScale.seed_scale()
