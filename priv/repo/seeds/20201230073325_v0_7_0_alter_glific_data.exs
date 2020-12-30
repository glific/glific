defmodule Glific.Repo.Seeds.AddGlificData_v0_7_0 do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Partners.Provider,
    Partners.Credential,
    Repo
  }

  def up(_repo) do
    update_existing_credentials()
    delete_provider()
  end

  defp update_existing_credentials() do
    credentials = Repo.all(Credential, skip_organization_id: true)

    credentials
    |> Enum.each(fn credential ->
      if Enum.member?([3, 5], credential.provider_id) do
        update_status(credential)
      end
    end)
  end

  defp update_status(credential) do
    Repo.update!(Ecto.Changeset.change(credential, %{is_active: false}))
  end

  defp delete_provider() do
    Repo.fetch_by(Provider, %{shortcode: "shortcode"})
    |> case do
      {:ok, provider} -> Repo.delete(provider)
      {:error, _} -> nil
    end
  end
end
