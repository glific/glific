defmodule Glific.Repo.Seeds.UpdateGupshupProvider do
  use Glific.Seeds.Seed

  alias Glific.{
    Partners.Provider,
    Repo
  }

  envs([:dev, :test, :prod])

  def up(_repo, opts) do
    update_gupshup_provider_config(opts)
  end

  @spec update_gupshup_provider_config(Keyword.t()) :: :ok
  defp update_gupshup_provider_config(opts) do
    # This doesnt have to run every time we seed for a new org
    if Keyword.get(opts, :tenant, nil) == "glific" do
      {:ok, gupshup} = Repo.fetch_by(Provider, %{shortcode: "gupshup"})

      # Removed api_end_point
      keys = Map.delete(gupshup.keys, "api_end_point") |> IO.inspect()

      Repo.update!(
        Ecto.Changeset.change(gupshup, %{
          keys: keys
        })
      )
    end

    :ok
  end
end
