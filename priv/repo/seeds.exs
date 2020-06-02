# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Glific.Repo.insert!(%Glific.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Glific.{
  Repo,
  Settings.Language
}

Repo.insert!(
  %Language{
    label: "English (United States)",
    locale: "en_US"
  })

Repo.insert!(
  %Language{
    label: "Hindi (India)",
    locale: "hi_IN"
  })
