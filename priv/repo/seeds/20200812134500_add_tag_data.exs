defmodule Glific.Repo.Seeds.AddTagData do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Templates.SessionTemplate,
    Repo,
    Settings.Language,
    Tags.Tag
  }

  def up(_repo) do
    languages = languages()
    gtags(languages)
  end

  def down(_repo) do
    statements = [
      "DELETE FROM tags WHERE label in ['Yes', 'No'];"
    ]

    Enum.each(statements, fn s -> Repo.query(s) end)
  end

  def languages,
    do: {
      Repo.fetch_by(Language, %{label: "Hindi"}),
      Repo.fetch_by(Language, %{label_locale: "English"})
    }

  def gtags(languages) do
    {_hi, {:ok, en_us}} = languages

    # seed tags
    {:ok, message_tags_mt} = Repo.fetch_by(Tag, %{label: "Messages"})

    tags = [
      # Intent of message
      %{
        label: "Yes",
        language_id: 2,
        parent_id: message_tags_mt.id,
        keywords: ["yes", "yeah", "okay", "ok"]
      },
      %{
        label: "No",
        language_id: 2,
        parent_id: message_tags_mt.id,
        keywords: ["no", "nope", "nay"]
      }
    ]
  end
end
