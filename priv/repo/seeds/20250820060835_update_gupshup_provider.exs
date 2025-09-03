defmodule Glific.Repo.Seeds.UpdateGupshupProvider do
  use Glific.Seeds.Seed

  alias Glific.{
    Partners.Provider,
    Repo
  }

  envs([:dev, :test, :prod])

  def up(_repo, _opts) do
    update_gupshup_provider_config()
  end

  @spec update_gupshup_provider_config() :: :ok
  defp update_gupshup_provider_config() do
    {:ok, gupshup} = Repo.fetch_by(Provider, %{shortcode: "gupshup"})

    # Removed api_end_point and added `hide: true` to hide the gupshup provider keys from UI for now.
    updated_keys =
      Enum.reduce(gupshup.keys, gupshup.keys, fn {k, v}, keys ->
        Map.put(keys, k, Map.put(v, :hide, true))
      end)
      |> Map.delete("api_end_point")

    gupshup
    |> Ecto.Changeset.change(%{keys: updated_keys})
    |> Repo.update!()

    :ok
  end
end
