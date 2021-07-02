defmodule Glific.Seeds.SeedsDg do
  @moduledoc """
  One shot migration of DG data
  """

  alias Glific.{
    Contacts.ContactsField,
    Groups.Group,
    Partners.Organization,
    Repo
  }

  @doc """
  Run the migration to populate the stats table for all active organizations
  """
  @spec seed_data([Organization.t()]) :: :ok
  def seed_data(organizations) do
    organizations
    |> Enum.each(fn organization ->
      Repo.put_organization_id(organization.id)

      seed_group(
        [
          "Stage 1",
          "Stage 2",
          "Stage 3",
          "adoption",
          "preventive",
          "curative",
          "Farmer",
          "Leaf curl check again"
        ],
        organization.id
      )

      seed_contact_fields(
        [
          "crop_stage",
          "enrolled_day",
          "next_flow",
          "next_flow_at",
          "initial_crop_day",
          "total_days",
          "invalid_response",
          "leafcurlsymptom",
          "no_response_farmer",
          "invalid_attempt"
        ],
        organization.id
      )
    end)
  end

  defp seed_group(group_list, org_id) do
    group_list
    |> Enum.each(fn label ->
      Repo.insert!(%Group{
        label: label,
        is_restricted: true,
        organization_id: org_id
      })
    end)
  end

  defp seed_contact_fields(contact_fields_list, org_id) do
    contact_fields_list
    |> Enum.each(fn name ->
      Repo.insert!(%ContactsField{
        name: name,
        shortcode: name,
        value_type: :text,
        scope: :contact,
        organization_id: org_id
      })
    end)
  end
end
