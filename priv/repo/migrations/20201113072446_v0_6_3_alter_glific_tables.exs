defmodule Glific.Repo.Migrations.V0_6_3_AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.6.2 Alter Glific tables
  """

  import Ecto.Query, warn: false

  alias Glific.{Contacts.Contact, Repo}

  def change do
    organizations()
  end

  defp organizations() do
    alter table(:organizations) do
      # add the signing phrase for webhooks
      # we will keep this encrypted, and remove the default before release
      add :signature_phrase, :string, default: "super secret"
    end

    # flush the change to the DB
    flush()

    from([o] in Organization,
      update: [set: [signature_phrase: "super secret"]]
    )
    |> Repo.update_all([], skip_organization_id: true)
  end

end
