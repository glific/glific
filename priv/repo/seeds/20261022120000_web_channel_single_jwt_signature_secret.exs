defmodule Glific.Repo.Seeds.WebChannelSingleJwtSignatureSecret do
  @moduledoc """
  Moves the web channel to one signing secret per organization: rewords the Settings page field,
  trims a credential that holds several secrets to its first, and gives every organization whose
  web channel is switched on a secret if it has none. Organizations that never enabled the channel
  are left alone; they get theirs when they do.
  """

  use Glific.Seeds.Seed

  import Ecto.Query

  alias Glific.{
    Partners.Credential,
    Partners.Provider,
    Repo,
    WebChannel.JwtSecret
  }

  envs([:dev, :test, :prod])

  tags([:web_channel])

  @doc """
  Rewords the secret field and settles each web channel credential on one secret.
  """
  @spec up(Ecto.Repo.t(), Keyword.t()) :: any()
  def up(_repo, _opts) do
    case Repo.fetch_by(Provider, %{shortcode: "web_channel"}) do
      {:ok, provider} ->
        provider
        |> Ecto.Changeset.change(%{secrets: secrets()})
        |> Repo.update!()

        settle_credentials(provider)

      _not_seeded ->
        :ok
    end
  end

  @spec settle_credentials(Provider.t()) :: :ok
  defp settle_credentials(provider) do
    from(c in Credential, where: c.provider_id == ^provider.id)
    |> Repo.all(skip_organization_id: true)
    |> Enum.each(&settle/1)
  end

  @spec settle(Credential.t()) :: any()
  defp settle(%Credential{secrets: secrets} = credential) do
    case JwtSecret.entries(secrets || %{}) do
      [] ->
        if credential.is_active,
          do: credential |> JwtSecret.ensure() |> log_result(credential, "generated a secret")

      [_only] ->
        :ok

      [first | _rest] ->
        credential
        |> Credential.changeset(%{secrets: Map.put(secrets, "jwt_signature_secrets", [first])})
        |> Repo.update()
        |> log_result(credential, "kept only the first of its secrets")
    end
  end

  @spec log_result(
          {:ok, Credential.t()} | {:error, Ecto.Changeset.t()},
          Credential.t(),
          String.t()
        ) ::
          :ok
  defp log_result({:ok, _credential}, credential, action) do
    Appsignal.Logger.info(
      "web_channel_secret",
      "Web channel credential of organization #{credential.organization_id} #{action}"
    )
  end

  defp log_result({:error, changeset}, credential, action) do
    Glific.log_error(
      "Web channel credential of organization #{credential.organization_id} could not be " <>
        "updated (#{action}): #{inspect(changeset.errors)}"
    )

    :ok
  end

  @spec secrets() :: map()
  defp secrets do
    %{
      "jwt_signature_secrets" => %{
        type: :list,
        label: "JWT signature secret",
        default: [],
        view_only: false,
        position: 1,
        helper_text:
          "The one secret your backend signs your users' login tokens with (HS256), at least 32 characters. It is created when the web channel is enabled. Replacing it signs every contact of your organization out."
      }
    }
  end
end
