defmodule Glific.CloakMigration do
  @moduledoc """
  Glific Cloak migration management on changing encryption keys
  """

  alias Glific.{
    Partners.Credential,
    Partners.Organization,
    Repo
  }

  @doc """
  migrate to new key for encryption
  Glific.CloakMigration.cloak_migrate()
  """
  @spec cloak_migrate :: :ok
  def cloak_migrate do
    Repo.all(Organization, skip_organization_id: true)
    |> Enum.each(fn organization -> update_organization(organization) end)

    Repo.all(Credential, skip_organization_id: true)
    |> Enum.each(fn credential -> update_credential(credential) end)

    :ok
  end

  defp update_credential(record) do
    record
    |> Credential.changeset(%{secrets: record.secrets})
    |> Repo.update(force: true)
  end

  defp update_organization(record) do
    record
    |> Organization.changeset(%{signature_phrase: record.signature_phrase})
    |> Repo.update(force: true)
  end
end
