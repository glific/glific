defmodule Glific.Repo.Migrations.AddStatusToMessages do
  use Ecto.Migration
  import Ecto.Query

  alias Glific.{Repo, Searches.SavedSearch}

  def change do
    messages()

    delete_tags()

    update_saved_search()
  end

  defp messages() do
    alter table(:messages) do
      # we only care about this for inbound messages
      add :is_read, :boolean, default: false
      # for inbound messages:
      #  - is_replied means that the org has replied to this message
      # for outbound messages:
      #  - is_replied means that the recipient has replied to this message
      add :is_replied, :boolean, default: false
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

  defp update_saved_search do
    ["Unread", "Not replied", "Not Responded", "Optout"]
    |> Enum.each(&update_shortcode/1)
  end

  def update_shortcode(shortcode) do
    args = %{
      filter: %{status: shortcode, term: ""},
      contactOpts: %{limit: 20, offset: 0},
      messageOpts: %{limit: 10, offset: 0}
    }

    query =
      SavedSearch
      |> where([s], s.shortcode == ^shortcode)
      |> Repo.update_all([set: [args: args]], skip_organization_id: true)
  end
end
