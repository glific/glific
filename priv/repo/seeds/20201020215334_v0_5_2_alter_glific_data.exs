defmodule Glific.Repo.Seeds.AddGlificData_v0_5_2 do
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
    {:ok, flow_tag} = Repo.fetch_by(Tag, %{shortcode: "flow", organization_id: organization_id})

    {:ok, en_us} = Repo.fetch_by(Language, %{label: "English (United States)"})

    feedback_tag =
      case Repo.fetch_by(Tag, %{shortcode: "feedback", organization_id: organization_id}) do
        {:ok, feedback_tag} ->
          feedback_tag

        {:error, _} ->
          Repo.insert!(%Tag{
            label: "Feedback",
            shortcode: "feedback",
            description: "Marking message received for the feedback flow",
            is_reserved: false,
            language_id: en_us.id,
            parent_id: flow_tag.id,
            organization_id: organization_id
          })
      end

    preference_tag =
      case Repo.fetch_by(Tag, %{shortcode: "preference", organization_id: organization_id}) do
        {:ok, preference_tag} ->
          preference_tag

        {:error, _} ->
          Repo.insert!(%Tag{
            label: "Preference",
            shortcode: "preference",
            description: "Marking message received for the preference flow",
            is_reserved: false,
            language_id: en_us.id,
            parent_id: flow_tag.id,
            organization_id: organization_id
          })
      end

    registration_tag =
      case Repo.fetch_by(Tag, %{shortcode: "registration", organization_id: organization_id}) do
        {:ok, registration_tag} ->
          registration_tag

        {:error, _} ->
          Repo.insert!(%Tag{
            label: "Registration",
            shortcode: "registration",
            description: "Marking message received for the registration flow",
            is_reserved: false,
            language_id: en_us.id,
            parent_id: flow_tag.id,
            organization_id: organization_id
          })
      end

    {:ok, optout_tag} =
      Repo.fetch_by(Tag, %{shortcode: "optout", organization_id: organization_id})

    Repo.update!(
      Ecto.Changeset.change(
        optout_tag,
        %{
          parent_id: flow_tag.id
        }
      )
    )

    {:ok, help_tag} = Repo.fetch_by(Tag, %{shortcode: "help", organization_id: organization_id})

    Repo.update!(
      Ecto.Changeset.change(
        help_tag,
        %{
          parent_id: flow_tag.id
        }
      )
    )

    {:ok, language_tag} =
      Repo.fetch_by(Tag, %{shortcode: "language", organization_id: organization_id})

    Repo.update!(
      Ecto.Changeset.change(
        language_tag,
        %{
          parent_id: flow_tag.id
        }
      )
    )

    if {:error, ["Elixir.Glific.Tags.Tag", "Resource not found"]} ==
         Repo.fetch_by(Tag, %{shortcode: "understood", organization_id: organization_id}) do
      Repo.insert!(%Tag{
        label: "Understood",
        shortcode: "understood",
        description: "Marking message received for the feedback flow: understood",
        is_reserved: false,
        language_id: en_us.id,
        parent_id: feedback_tag.id,
        organization_id: organization_id
      })
    end

    if {:error, ["Elixir.Glific.Tags.Tag", "Resource not found"]} ==
         Repo.fetch_by(Tag, %{shortcode: "notunderstood", organization_id: organization_id}) do
      Repo.insert!(%Tag{
        label: "Not Understood",
        shortcode: "notunderstood",
        description: "Marking message received for the feedback flow: not understood",
        is_reserved: false,
        language_id: en_us.id,
        parent_id: feedback_tag.id,
        organization_id: organization_id
      })
    end

    if {:error, ["Elixir.Glific.Tags.Tag", "Resource not found"]} ==
         Repo.fetch_by(Tag, %{shortcode: "confirmoptout", organization_id: organization_id}) do
      Repo.insert!(%Tag{
        label: "Confirm Optout",
        shortcode: "confirmoptout",
        description: "Marking message received for the optout flow: confirm optout",
        is_reserved: false,
        language_id: en_us.id,
        parent_id: optout_tag.id,
        organization_id: organization_id
      })
    end

    if {:error, ["Elixir.Glific.Tags.Tag", "Resource not found"]} ==
         Repo.fetch_by(Tag, %{shortcode: "canceloptout", organization_id: organization_id}) do
      Repo.insert!(%Tag{
        label: "Cancel Optout",
        shortcode: "canceloptout",
        description: "Marking message received for the optout flow: cancel optout",
        is_reserved: false,
        language_id: en_us.id,
        parent_id: optout_tag.id,
        organization_id: organization_id
      })
    end

    if {:error, ["Elixir.Glific.Tags.Tag", "Resource not found"]} ==
         Repo.fetch_by(Tag, %{shortcode: "agegrouplessthan10", organization_id: organization_id}) do
      Repo.insert!(%Tag{
        label: "Age Group less than 10",
        shortcode: "agegrouplessthan10",
        description: "Marking message received for the registration flow: age group less than 10",
        is_reserved: false,
        language_id: en_us.id,
        parent_id: registration_tag.id,
        organization_id: organization_id
      })
    end

    if {:error, ["Elixir.Glific.Tags.Tag", "Resource not found"]} ==
         Repo.fetch_by(Tag, %{shortcode: "agegroup11to14", organization_id: organization_id}) do
      Repo.insert!(%Tag{
        label: "Age Group 11 to 14",
        shortcode: "agegroup11to14",
        description: "Marking message received for the registration flow: age group 11 to 14",
        is_reserved: false,
        language_id: en_us.id,
        parent_id: registration_tag.id,
        organization_id: organization_id
      })
    end

    if {:error, ["Elixir.Glific.Tags.Tag", "Resource not found"]} ==
         Repo.fetch_by(Tag, %{shortcode: "agegroup15to18", organization_id: organization_id}) do
      Repo.insert!(%Tag{
        label: "Age Group 15 to 18",
        shortcode: "agegroup15to18",
        description: "Marking message received for the registration flow: Age Group 15 to 18",
        is_reserved: false,
        language_id: en_us.id,
        parent_id: registration_tag.id,
        organization_id: organization_id
      })
    end

    if {:error, ["Elixir.Glific.Tags.Tag", "Resource not found"]} ==
         Repo.fetch_by(Tag, %{shortcode: "agegroup19orabove", organization_id: organization_id}) do
      Repo.insert!(%Tag{
        label: "Age Group 19 or above",
        shortcode: "agegroup19orabove",
        description: "Marking message received for the registration flow: age group 19 or above",
        is_reserved: false,
        language_id: en_us.id,
        parent_id: registration_tag.id,
        organization_id: organization_id
      })
    end
  end
end
