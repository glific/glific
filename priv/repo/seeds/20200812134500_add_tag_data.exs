defmodule Glific.Repo.Seeds.AddTagData do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Templates.SessionTemplate
  }

  def up(_repo) do
    languages = languages()

    tags(languages)
  end

  def down(_repo) do
    statements = [
      "DELETE FROM tags WHERE label in ['Yes', 'No'];"
    ]

    Enum.each(statements, fn s -> Repo.query(s) end)
  end

  def languages,
    do: {
      Repo.get_by(Language, %{label: "Hindi"}),
      Repo.get_by(Language, %{label_locale: "English"})
    }

  def tags(languages) do
    {_hi, en_us} = languages

    # seed tags
    message_tags_mt = Repo.get_by(Tag, %{label: "Messages"})

    tags = [
      # Intent of message
      %{
        label: "Yes",
        language_id: en_us.id,
        parent_id: message_tags_mt.id,
        keywords: ["yes", "yeah", "okay", "ok"]
      },
      %{
        label: "No",
        language_id: en_us.id,
        parent_id: message_tags_mt.id,
        keywords: ["no", "nope", "nay"]
      }
    ]
  end
end
