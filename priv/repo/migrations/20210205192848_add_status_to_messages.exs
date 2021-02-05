defmodule Glific.Repo.Migrations.AddStatusToMessages do
  use Ecto.Migration

  def change do
    messages()
  end

  def messages() do
    alter table(:messages) do
      # we only care about this for inbound messages
      add :is_read, :boolean, default: false
      # for inbound messages:
      #  - is_replied means that the org has replied to this message
      # for outbound messages:
      #  - is_replied means that the recipient has replied to this message
      add :is_replied, :boolean, default: false
    end

    create index(:messages, :is_read)
    # since we'll always use is_replied in combination with a flow, we add a combined index
    create index(:messages, [:is_replied, :flow]
  end
end
