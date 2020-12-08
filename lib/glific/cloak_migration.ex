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
    |> Enum.each(fn organization -> update_record(organization) end)

    Glific.Repo.all(Glific.Partners.Credential)
    |> Enum.each(fn credential -> update_record(credential) end)

    :ok
  end


  defp update_record(record),
    do: record
      |> Repo.update(record, [force: true])

end
