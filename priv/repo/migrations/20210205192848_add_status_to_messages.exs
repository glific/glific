defmodule Glific.Repo.Migrations.AddStatusToMessages do
  use Ecto.Migration

  def change do
    messages()

    delete_tags()
  end

  defp messages() do
    alter table(:messages) do
      # we only care about this for inbound messages
      add :is_read, :boolean,
        default: false,
        comment: "Whether the message was read (inbound messages)"

      # for inbound messages:
      #  - is_replied means that the org has replied to this message
      # for outbound messages:
      #  - is_replied means that the recipient has replied to this message
      add :is_replied, :boolean,
        default: false,
        comment:
          "For inbound messages - whether organisation has replied to the message; for outbound message - Whether recipient has replied to the message"
    end

    create index(:messages, [:is_read, :flow])
    # since we'll always use is_replied in combination with a flow, we add a combined index
    create index(:messages, [:is_replied, :flow])
  end

  defp delete_tags() do
    """
    DELETE FROM tags
    WHERE shortcode IN ('unread', 'notreplied', 'notresponded')
    """
    |> execute()
  end
end
