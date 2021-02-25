defmodule Glific.Repo.Seeds.DisableChatbase do
  use Glific.Seeds.Seed

  envs([:dev, :test, :prod])

  alias Glific.{
    Partners.Credential,
    Repo
  }

  def up(_repo) do
    update_existing_credentials()
  end

  defp update_existing_credentials() do
    credentials = Repo.all(Credential, skip_organization_id: true) |> Repo.preload(:provider)

    credentials
    |> Enum.each(fn credential ->
      if Enum.member?(["chatbase"], credential.provider.shortcode) do
        Repo.update!(Ecto.Changeset.change(credential, %{is_active: false, is_valid: false}))
      end
    end)
  end
end
