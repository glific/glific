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
    Repo.all(Organization, skip_organization_id: true)
    |> Enum.each(fn organization -> update_organization(organization) end)

    Repo.all(Credential, skip_organization_id: true)
    |> Enum.each(fn credential -> update_credential(credential) end)

    :ok
  end

  @spec update_credential(Credential.t()) :: {:ok, Credential.t()}
  defp update_credential(record) do
    Partners.update_credential(record, %{secrets: %{temp: nil}})
    Partners.update_credential(record, %{secrets: record.secrets}})
  end

  @spec update_credential(Organization.t()) :: {:ok, Organization.t()}
  defp update_organization(record) do
    Partners.update_organization(record, %{signature_phrase: nil})
    Partners.update_organization(record, %{signature_phrase: record.signature_phrase})
  end
end
