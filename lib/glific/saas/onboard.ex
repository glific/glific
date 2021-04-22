defmodule Glific.Saas.Onboard do
  @moduledoc """
  For now, we will build this on top of organization table, and have a group of helper functions
  here to manage global operations across all organizations.
  At some later point, we might decide to have a separate onboarding table and managment structure
  """
  alias Glific.{
    Contacts.Contact,
    Partners,
    Partners.Organization,
    Saas.Queries
  }

  @doc """
  Setup all the tables and necessary values to onboard an organization
  """
  @spec setup(map()) :: map()
  def setup(params) do
    params = Glific.atomize_keys(params)

    %{is_valid: true, messages: []}
    |> Queries.validate(params)
    |> Queries.setup(params)
    |> format_results()
  end

  @spec add_map(map(), atom(), boolean()) :: map()
  defp add_map(map, _key, nil), do: map
  defp add_map(map, key, value), do: Map.put(map, key, value)

  @doc """
  Update the active and/or approved status of an organization
  """
  @spec status(map()) :: Organization.t() | nil
  def status(%{
        org_id: org_id,
        is_active: is_active,
        is_approved: is_approved
      }) do
    changes =
      %{}
      |> add_map(:is_active, is_active)
      |> add_map(:is_approved, is_approved)

    {:ok, organization} =
      org_id
      |> Partners.get_organization!()
      |> Partners.update_organization(changes)

    organization
  end

  @doc """
  Delete an organization from the DB, ensure that the confirmed flag is set
  since this is a super destructive operation
  """
  @spec delete(map()) :: {:ok, Organization.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def delete(%{org_id: org_id, is_confirmed: true}) do
    organization = Partners.get_organization!(org_id)

    # ensure that the organization is not active, our last check before we
    # blow it away
    if organization.is_active do
      {:error, "Organization is still active"}
    else
      Partners.delete_organization(organization)
    end
  end

  def delete(_params), do: {:error, "Cannot delete organization"}

  @spec format_results(map()) :: map()
  defp format_results(%{is_valid: true} = results) do
    results
    |> Map.put(:organization, Organization.to_minimal_map(results.organization))
    |> Map.put(:contact, Contact.to_minimal_map(results.contact))
    |> Map.put(:credential, "Gupshup secrets has been added.")
  end

  defp format_results(results), do: results
end
