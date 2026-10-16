defmodule Glific.Repo.Seeds.AddWebChannelJwtSignatureSecrets do
  @moduledoc """
  Adds the JWT signature secrets an organization signs its own users' web channel login tokens with
  to the `web_channel` provider, so its admin can set and rotate them on the Settings page. They are
  one list of named secrets, kept encrypted; the branding keys the provider already has are left as
  they are.
  """

  use Glific.Seeds.Seed

  alias Glific.{
    Partners.Provider,
    Repo
  }

  envs([:dev, :test, :prod])

  tags([:web_channel])

  @rotation_help "A token signed with any of them is accepted. To rotate, add the new secret, switch your backend to it, then remove the old one."

  @doc """
  Adds the JWT signature secrets list to the web channel provider.
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
      "jwt_signature_secrets" => %{
        type: :list,
        label: "JWT signature secrets",
        default: [],
        view_only: false,
        position: 1,
        helper_text:
          "Named secrets your backend signs your users' login tokens with (HS256), each at least 32 characters; a shorter one is ignored. Leave the list empty to allow only phone + OTP sign-in. " <>
            @rotation_help
      }
    }
  end
end
