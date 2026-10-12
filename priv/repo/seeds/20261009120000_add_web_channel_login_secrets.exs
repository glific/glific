defmodule Glific.Repo.Seeds.AddWebChannelLoginSecrets do
  @moduledoc """
  Adds the secrets an organization signs its own users' web channel login tokens with to the
  `web_channel` provider, so its admin can set and rotate them on the Settings page.
  """

  use Glific.Seeds.Seed

  alias Glific.{
    Partners.Provider,
    Repo
  }

  envs([:dev, :test, :prod])

  tags([:web_channel])

  @doc """
  Sets the web channel provider's secrets.
  """
  @spec up(Ecto.Repo.t(), Keyword.t()) :: any()
  def up(_repo, _opts) do
    case Repo.fetch_by(Provider, %{shortcode: "web_channel"}) do
      {:ok, provider} ->
        provider
        |> Ecto.Changeset.change(%{secrets: secrets()})
        |> Repo.update!()

      _not_seeded ->
        :ok
    end
  end

  @spec secrets() :: map()
  defp secrets do
    %{
      login_secret: %{
        type: :string,
        label: "Login secret",
        default: nil,
        view_only: false,
        position: 1,
        helper_text:
          "Your backend signs your users' login tokens with this (HS256). Leave empty to allow only phone + OTP sign-in."
      },
      previous_login_secret: %{
        type: :string,
        label: "Previous login secret",
        default: nil,
        view_only: false,
        position: 2,
        helper_text:
          "While rotating, put the old secret here so tokens signed with it keep working, then clear it."
      }
    }
  end
end
