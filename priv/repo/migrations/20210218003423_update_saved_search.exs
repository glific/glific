defmodule Glific.Repo.Migrations.UpdateSavedSearch do
  use Ecto.Migration

  import Ecto.Query

  alias Glific.{Repo, Searches.SavedSearch}

  def change do
    update_saved_search()
  end

  defp update_saved_search do
    ["All", "Unread", "Not replied", "Not Responded", "Optout"]
    |> Enum.each(&update_shortcode/1)
  end

  def update_shortcode(shortcode) do
    args = %{
      filter: %{status: shortcode, term: ""},
      contactOpts: %{limit: 25, offset: 0},
      messageOpts: %{limit: 20, offset: 0}
    }

    SavedSearch
    |> where([s], s.shortcode == ^shortcode)
    |> Repo.update_all([set: [args: args]], skip_organization_id: true)
  end
end
