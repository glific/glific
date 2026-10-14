defmodule Glific.Repo.Seeds.AddWebChannelJwtSignatureSecrets do
  @moduledoc """
  Adds the two JWT signature secret slots an organization signs its own users' web channel login tokens
  with to the `web_channel` provider, so its admin can set and rotate them on the Settings page.
  Each slot is a name (a key, kept plain) and a secret (kept encrypted); the branding keys the
  provider already has are left as they are.
  """

  use Glific.Seeds.Seed

  alias Glific.{
    Partners.Provider,
    Repo
  }

  envs([:dev, :test, :prod])

  tags([:web_channel])

  @rotation_help "A token signed with either secret is accepted. To rotate, put the new secret in the empty slot, switch your backend over to it, then clear the old one."

  @doc """
  Adds the JWT signature secret slots to the web channel provider.
  """
  @spec up(Ecto.Repo.t(), Keyword.t()) :: any()
  def up(_repo, _opts) do
    case Repo.fetch_by(Provider, %{shortcode: "web_channel"}) do
      {:ok, provider} ->
        provider
        |> Ecto.Changeset.change(%{
          keys: Map.merge(provider.keys || %{}, keys()),
          secrets: secrets()
        })
        |> Repo.update!()

      _not_seeded ->
        :ok
    end
  end

  @spec keys() :: map()
  defp keys do
    %{
      "jwt_signature_secret_1_name" => name_field("JWT signature secret 1 name", 10),
      "jwt_signature_secret_2_name" => name_field("JWT signature secret 2 name", 11)
    }
  end

  @spec secrets() :: map()
  defp secrets do
    %{
      "jwt_signature_secret_1" => secret_field("JWT signature secret 1", 1),
      "jwt_signature_secret_2" => secret_field("JWT signature secret 2", 2)
    }
  end

  @spec name_field(String.t(), pos_integer()) :: map()
  defp name_field(label, position) do
    %{
      type: :string,
      label: label,
      default: nil,
      view_only: false,
      position: position,
      helper_text:
        "A name of your choice to tell this key apart, for example the year it was issued."
    }
  end

  @spec secret_field(String.t(), pos_integer()) :: map()
  defp secret_field(label, position) do
    %{
      type: :string,
      label: label,
      default: nil,
      view_only: false,
      position: position,
      helper_text:
        "Your backend signs your users' login tokens with this (HS256). Leave both empty to allow only phone + OTP sign-in. " <>
          @rotation_help
    }
  end
end
