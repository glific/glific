defmodule Glific.WebChannel.JwtSecret do
  @moduledoc """
  The one secret an organization's web channel tokens are signed with, kept in the
  `jwt_signature_secrets` list of its `web_channel` credential.

  The list shape is the one the Settings page edits; a credential holds at most one entry, so
  replacing it signs every contact of the organization out. It is created when the channel is
  switched on and left in place if the channel is switched off again.
  """

  alias Glific.{Partners, Partners.Credential, Repo}

  @provider_code "web_channel"
  @secrets_key "jwt_signature_secrets"
  @min_length 32
  @generated_bytes 32

  @doc """
  The organization's signing secret, or `:error` when it has none that is long enough.
  """
  @spec fetch(non_neg_integer()) :: {:ok, String.t()} | :error
  def fetch(organization_id) do
    with %{services: services} <- Partners.organization(organization_id),
         secrets when is_map(secrets) <- get_in(services, [@provider_code, :secrets]),
         [entry | _rest] <- entries(secrets),
         secret when is_binary(secret) <- secret_of(entry),
         true <- String.length(secret) >= @min_length do
      {:ok, secret}
    else
      _no_usable_secret -> :error
    end
  end

  @doc """
  Gives a credential a freshly generated secret unless it already has one.
  """
  @spec ensure(Credential.t()) :: {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def ensure(%Credential{secrets: secrets} = credential) do
    secrets = secrets || %{}

    if entries(secrets) == [] do
      credential
      |> Credential.changeset(%{secrets: Map.put(secrets, @secrets_key, [generated_entry()])})
      |> Repo.update()
    else
      {:ok, credential}
    end
  end

  @doc """
  The entries of a credential's secrets that carry a signing secret.
  """
  @spec entries(map()) :: [map()]
  def entries(secrets), do: List.wrap(secrets[@secrets_key] || secrets[:jwt_signature_secrets])

  @doc """
  Why a credential cannot go from `old_secrets` to `new_secrets`: more than one secret, a secret
  shorter than the minimum, or a saved secret removed. Empty when the change is allowed.
  """
  @spec validate_new_secret(map() | nil, map() | nil) :: [String.t()]
  def validate_new_secret(old_secrets, new_secrets) do
    old_entries = entries(old_secrets || %{})
    new_entries = entries(new_secrets || %{})

    cond do
      length(new_entries) > 1 ->
        ["Only one JWT signature secret is allowed"]

      new_entries == [] and old_entries != [] ->
        ["The JWT signature secret can be replaced but not removed"]

      Enum.any?(new_entries, &(String.length(secret_of(&1) || "") < @min_length)) ->
        ["The JWT signature secret must be at least #{@min_length} characters"]

      true ->
        []
    end
  end

  @spec generated_entry() :: map()
  defp generated_entry do
    %{
      "name" => "Signing secret",
      "secret" =>
        @generated_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    }
  end

  @spec secret_of(any()) :: String.t() | nil
  defp secret_of(%{"secret" => secret}), do: secret
  defp secret_of(%{secret: secret}), do: secret
  defp secret_of(_entry), do: nil
end
