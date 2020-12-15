defmodule Glific.CloakMigration do
  @moduledoc """
  Glific Cloak migration management on changing encryption keys
  """

  alias Glific.{
    Partners,
    Partners.Credential,
    Partners.Organization,
    Repo
  }

  @doc """
  migrate to new key for encryption
  """
  @spec cloak_migrate :: :ok
  def cloak_migrate do
    organizations = Glific.Repo.all(Glific.Partners.Organization, skip_organization_id: true)

    organizations |> Enum.each(fn organization -> update_organization(organization) end)

    organizations_list =
      Enum.reduce(organizations, %{}, fn organization, acc ->
        Map.put(acc, organization.id, organization.shortcode)
      end)

    Repo.all(Credential, skip_organization_id: true)
    |> Enum.each(fn credential -> update_credential(credential, organizations_list) end)

    :ok
  end

  @spec update_credential(Credential.t(), map()) :: any()
  defp update_credential(credential, organizations_list) do
    {:ok, updated} =
      credential
      |> Credential.changeset(%{secrets: %{}})
      |> Repo.update(force: true)

    updated
    |> Credential.changeset(%{secrets: credential.secrets})
    |> Repo.update(force: true)

    Partners.remove_organization_cache(
      credential.organization_id,
      Map.get(organizations_list, credential.organization_id)
    )
  end

  @spec update_organization(Organization.t()) ::
          {:ok, Organization.t()} | {:error, Ecto.Changeset.t()}
  defp update_organization(organization) do
    Partners.update_organization(organization, %{signature_phrase: nil})
    Partners.update_organization(organization, %{signature_phrase: organization.signature_phrase})
  end
end
