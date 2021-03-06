defmodule Glific.Repo.Migrations.V0_7_2_AlterGlificTables do
  use Ecto.Migration

  @moduledoc """
  v0.7.2 Alter Glific tables
  """

  import Ecto.Query, warn: false

  alias Glific.{Contacts.Contact, Repo}

  def change do
    users()

    contacts()

    organizations()

    webhook_logs()
  end

  defp users() do
    alter table(:users) do
      add :is_restricted, :boolean, default: false
    end
  end

  def contacts() do
    alter table(:contacts) do
      add :last_communication_at, :utc_datetime
    end

    # flush the change to the DB
    flush()

    from([c] in Contact,
      update: [set: [last_communication_at: c.last_message_at]]
    )
    |> Repo.update_all([], skip_organization_id: true)
  end

  defp organizations() do
    alter table(:organizations) do
      # add the signing phrase for webhooks
      # we will keep this encrypted, and remove the default before release
      add :signature_phrase, :binary
    end
  end

  defp webhook_logs() do
    alter table(:webhook_logs) do
      modify :request_headers, :jsonb, default: "{}"
    end
  end
end
