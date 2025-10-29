defmodule Glific.Seeds.Seeds20251029115500CleanupProviders do
  use Glific.Seeds.Seed

  import Ecto.Query

  alias Glific.{
    Partners.Credential,
    Partners.Provider,
    Repo
  }

  # Run on all envs
  envs([:dev, :test, :prod])

  @doc false
  def up(_repo, _opts) do
    remove_unwanted_providers()
    fix_google_sheet_name()
  end

  @doc false
  def down(_repo, _opts) do
    :ok
  end

  @spec remove_unwanted_providers() :: any()
  defp remove_unwanted_providers() do
    names_to_remove = [
      "OpenAI (ChatGPT)(Beta)",
      "Navana Tech",
      "Gupshup Enterprise",
      "GoogleASR",
      "Dialogflow"
    ]

    from(p in Provider, where: p.name in ^names_to_remove)
    |> Repo.all()
    |> Enum.each(&delete_provider_and_credentials/1)
  end

  @spec delete_provider_and_credentials(Provider.t()) :: any()
  defp delete_provider_and_credentials(%Provider{id: provider_id} = provider) do
    from(c in Credential, where: c.provider_id == ^provider_id)
    |> Repo.delete_all()

    Repo.delete(provider)
  end

  @spec fix_google_sheet_name() :: any()
  defp fix_google_sheet_name() do
    from(p in Provider, where: p.shortcode == "google_sheets")
    |> Repo.one()
    |> case do
      nil ->
        :ok

      %Provider{} = provider ->
        changeset = Ecto.Changeset.change(provider, %{name: "Google Sheet"})
        Repo.update(changeset)
    end
  end
end
