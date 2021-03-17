defmodule Glific.Repo.Migrations.UpdateAllSavedSearchArgs do
  use Ecto.Migration

  import Ecto.Query

  alias Glific.{Repo, Searches.SavedSearch}

  def change do
    update_all_saved_search_args()
  end

  def update_all_saved_search_args() do
    shortcode = "All"

    args = %{
      filter: %{},
      contactOpts: %{limit: 25},
      messageOpts: %{limit: 20}
    }

    SavedSearch
    |> where([s], s.shortcode == ^shortcode)
    |> Repo.update_all([set: [args: args]], skip_organization_id: true)
  end
end
