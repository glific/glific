defmodule Glific.Repo.Seeds.AddGlificData_v0_5_1 do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Partners,
    Settings.Language,
    Tags.Tag,
    Repo
  }

  def up(_repo) do
    Partners.list_organizations()
    |> Enum.each(fn organization -> add_tags(organization) end)
  end

  defp add_tags(organization) do
    {:ok, message_tags_mt} =
      Repo.fetch_by(Tag, %{shortcode: "messages", organization_id: organization.id})

    {:ok, en_us} = Repo.fetch_by(Language, %{label: "English (United States)"})

    message_tags_flow =
      Repo.insert!(%Tag{
        label: "Flow",
        shortcode: "flow",
        description: "Marking message received for a flow",
        is_reserved: false,
        language_id: en_us.id,
        parent_id: message_tags_mt.id,
        organization_id: organization.id
      })

    message_tags_flow_activity =
      Repo.insert!(%Tag{
        label: "Activities",
        shortcode: "activities",
        description: "Marking message received for an activity",
        is_reserved: false,
        language_id: en_us.id,
        parent_id: message_tags_flow.id,
        organization_id: organization.id
      })

    Repo.insert!(%Tag{
      label: "Languages",
      shortcode: "languages",
      description: "Marking message received for the language flow",
      is_reserved: false,
      language_id: en_us.id,
      parent_id: message_tags_flow.id,
      organization_id: organization.id
    })

    tags = [
      # flow tags
      %{
        label: "Poetry",
        shortcode: "poetry",
        description: "Marking message received for the activity: poetry",
        parent_id: message_tags_flow_activity.id
      },
      %{
        label: "Visual Arts",
        shortcode: "visualarts",
        description: "Marking message received for the activity: visual arts",
        parent_id: message_tags_flow_activity.id
      },
      %{
        label: "Theatre",
        shortcode: "theatre",
        description: "Marking message received for the activity: theatre",
        parent_id: message_tags_flow_activity.id
      }
    ]

    utc_now = DateTime.utc_now() |> DateTime.truncate(:second)

    tags =
      Enum.map(
        tags,
        fn tag ->
          tag
          |> Map.put(:organization_id, organization.id)
          |> Map.put(:language_id, en_us.id)
          |> Map.put(:is_reserved, false)
          |> Map.put(:inserted_at, utc_now)
          |> Map.put(:updated_at, utc_now)
        end
      )

    # seed multiple tags
    Repo.insert_all(Tag, tags)
  end
end
