defmodule Glific.CloakMigration do
  @moduledoc """
  Glific Cloak migration management on changing encryption keys
  """
  import Ecto.Changeset

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
    Glific.Repo.all(Glific.Partners.Organization)
    |> Enum.each(fn organization -> update_signature_phrase(organization) end)

    Glific.Repo.all(Glific.Partners.Credential)
    |> Enum.each(fn credential -> update_secrets(credential) end)

    :ok
  end

  defp update_signature_phrase(organization) do
    {:ok, updated} =
      organization
      |> Organization.changeset(%{signature_phrase: "test signature"})
      |> Repo.update(skip_organization_id: true)

    updated
    |> Organization.changeset(%{signature_phrase: organization.signature_phrase})
    |> Repo.update(skip_organization_id: true)
  end

  defp update_secrets(credential) do
    {:ok, updated} =
      credential
      |> Credential.changeset(%{secrets: %{name: "test secrets"}})
      |> Repo.update(skip_organization_id: true)

    updated
    |> Credential.changeset(%{secrets: credential.secrets})
    |> Repo.update(skip_organization_id: true)
  end
