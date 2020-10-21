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
    Partners.active_organizations()
    |> Enum.each(fn {organization_id, _name} -> add_tags(organization_id) end)
  end

  defp add_tags(organization_id) do
    {:ok, messages_tag} =
      Repo.fetch_by(Tag, %{shortcode: "messages", organization_id: organization_id})

    {:ok, en_us} = Repo.fetch_by(Language, %{label: "English (United States)"})

    flow_tag =
      case Repo.fetch_by(Tag, %{shortcode: "flow", organization_id: organization_id}) do
        {:ok, flow_tag} ->
          flow_tag

        {:error, _} ->
          Repo.insert!(%Tag{
            label: "Flow",
            shortcode: "flow",
            description: "Marking message received for a flow",
            is_reserved: true,
            language_id: en_us.id,
            parent_id: messages_tag.id,
            organization_id: organization_id
          })
      end

    flow_activity_tag =
      case Repo.fetch_by(Tag, %{shortcode: "activities", organization_id: organization_id}) do
        {:ok, flow_tag} ->
          flow_tag

        {:error, _} ->
          Repo.insert!(%Tag{
            label: "Activities",
            shortcode: "activities",
            description: "Marking message received for an activity",
            is_reserved: false,
            language_id: en_us.id,
            parent_id: flow_tag.id,
            organization_id: organization_id
          })
      end

    if {:error, ["Elixir.Glific.Tags.Tag", "Resource not found"]} ==
         Repo.fetch_by(Tag, %{shortcode: "poetry", organization_id: organization_id}) do
      Repo.insert!(%Tag{
        label: "Poetry",
        shortcode: "poetry",
        description: "Marking message received for the activity: poetry",
        is_reserved: false,
        language_id: en_us.id,
        parent_id: flow_activity_tag.id,
        organization_id: organization_id
      })
    end

    if {:error, ["Elixir.Glific.Tags.Tag", "Resource not found"]} ==
         Repo.fetch_by(Tag, %{shortcode: "visualarts", organization_id: organization_id}) do
      Repo.insert!(%Tag{
        label: "Visual Arts",
        shortcode: "visualarts",
        description: "Marking message received for the activity: visual arts",
        is_reserved: false,
        language_id: en_us.id,
        parent_id: flow_activity_tag.id,
        organization_id: organization_id
      })
    end

    if {:error, ["Elixir.Glific.Tags.Tag", "Resource not found"]} ==
         Repo.fetch_by(Tag, %{shortcode: "theatre", organization_id: organization_id}) do
      Repo.insert!(%Tag{
        label: "Theatre",
        shortcode: "theatre",
        description: "Marking message received for the activity: theatre",
        is_reserved: false,
        language_id: en_us.id,
        parent_id: flow_activity_tag.id,
        organization_id: organization_id
      })
    end
  end
end
