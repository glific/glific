defmodule GlificWeb.WebChannel.Token do
  @moduledoc """
  Signs and verifies every JWT that authenticates a browser contact on the web channel, whether
  an NGO's backend minted it or Glific did after a phone and one-time code login.

  Both are HS256 tokens signed with the organization's own secret (`Glific.WebChannel.JwtSecret`)
  and both name the contact by `sub`, the contact's web identity. The organization is the
  request's, never the token's, and an organization without a secret verifies nothing. The
  token's own `alg` is never trusted. Every way a token can be wrong gives `{:error, :invalid}`.

  A token lives at most 24 hours, with 60 seconds of clock leeway. A Glific session token also
  carries `jti` (the session) and `sst` (when the session started): it lasts one hour, and
  `renew/3` refreshes it only until the session is 24 hours old.
  """

  alias Glific.{Contacts, WebChannel.JwtSecret}
  alias JOSE.{JWK, JWS, JWT}

  @algorithm "HS256"
  @channel "web"
  @max_lifetime_seconds 86_400
  @session_ttl_seconds 3_600
  @session_max_seconds 86_400
  @leeway_seconds 60
  @max_length 255

  @type claims :: %{
          required(:sub) => String.t(),
          required(:exp) => integer(),
          optional(:name) => String.t(),
          optional(:phone) => String.t(),
          optional(:session_id) => String.t(),
          optional(:session_started_at) => integer()
        }

  @doc """
  The claims of a token signed with the organization's secret, if it is valid now.
  """
  @spec verify(non_neg_integer(), String.t() | nil, integer()) ::
          {:ok, claims()} | {:error, :invalid}
  def verify(organization_id, token, now \\ System.system_time(:second))

  def verify(organization_id, token, now) when is_binary(token) and token != "" do
    with {:ok, secret} <- JwtSecret.fetch(organization_id),
         {:ok, fields} <- verify_signature(secret, token),
         :ok <- validate_timing(fields, now),
         {:ok, claims} <- extract_claims(fields),
         :ok <- validate_session(claims, now) do
      {:ok, claims}
    else
      _invalid -> {:error, :invalid}
    end
  end

  def verify(_organization_id, _token, _now), do: {:error, :invalid}

  @doc """
  Signs a token for `claims` (`:sub`, optionally `:name`, `:phone`, `:session_id` and
  `:session_started_at`) with the organization's secret, issued now unless `:iat` is given and
  expiring after `:exp`, or after one hour when that is absent.
  """
  @spec sign(non_neg_integer(), map()) :: {:ok, String.t()} | {:error, :no_secret}
  def sign(organization_id, claims) do
    with {:ok, secret} <- fetch_secret(organization_id) do
      issued_at = Map.get(claims, :iat, System.system_time(:second))

      fields =
        %{
          "sub" => claims.sub,
          "channel" => @channel,
          "name" => claims[:name],
          "phone" => claims[:phone],
          "jti" => claims[:session_id],
          "sst" => claims[:session_started_at],
          "iat" => issued_at,
          "exp" => Map.get(claims, :exp, issued_at + @session_ttl_seconds)
        }
        |> Map.reject(fn {_key, value} -> is_nil(value) end)

      {_jws, token} =
        secret
        |> JWK.from_oct()
        |> JWT.sign(%{"alg" => @algorithm}, fields)
        |> JWS.compact()

      {:ok, token}
    end
  end

  @doc """
  Generates a one hour token for the contact's web identity `sub`, renewable for 24 hours.
  """
  @spec generate(non_neg_integer(), String.t()) :: {:ok, String.t()} | {:error, :no_secret}
  def generate(organization_id, sub) do
    sign(organization_id, %{
      sub: sub,
      session_id: Ecto.UUID.generate(),
      session_started_at: System.system_time(:second)
    })
  end

  @doc """
  Exchanges a valid Glific session token for a fresh one in the same session.

  `jti` and `sst` carry over: a new `jti` would make every refresh look like a second login, and
  a new `sst` would make renewal unbounded. A token with no session claims is refused, since
  renewing an NGO's token is its backend's job.
  """
  @spec renew(non_neg_integer(), String.t() | nil, integer()) ::
          {:ok, String.t(), claims()} | {:error, :invalid}
  def renew(organization_id, token, now \\ System.system_time(:second)) do
    with {:ok, %{session_id: _, session_started_at: _} = claims} <-
           verify(organization_id, token, now),
         {:ok, renewed} <- sign(organization_id, claims |> Map.delete(:exp) |> Map.put(:iat, now)) do
      {:ok, renewed, claims}
    else
      _refused -> {:error, :invalid}
    end
  end

  @spec fetch_secret(non_neg_integer()) :: {:ok, String.t()} | {:error, :no_secret}
  defp fetch_secret(organization_id) do
    case JwtSecret.fetch(organization_id) do
      {:ok, secret} -> {:ok, secret}
      :error -> {:error, :no_secret}
    end
  end

  @spec verify_signature(String.t(), String.t()) :: {:ok, map()} | :error
  defp verify_signature(secret, token) do
    case JWT.verify_strict(JWK.from_oct(secret), [@algorithm], token) do
      {true, %JWT{fields: fields}, _jws} -> {:ok, fields}
      _unverified -> :error
    end
  rescue
    _malformed -> :error
  end

  @spec validate_timing(map(), integer()) :: :ok | :error
  defp validate_timing(%{"iat" => iat, "exp" => exp}, now)
       when is_integer(iat) and is_integer(exp) do
    if exp - iat <= @max_lifetime_seconds and iat <= now + @leeway_seconds and
         exp > now - @leeway_seconds,
       do: :ok,
       else: :error
  end

  defp validate_timing(_fields, _now), do: :error

  @spec extract_claims(map()) :: {:ok, claims()} | :error
  defp extract_claims(%{"sub" => sub, "channel" => @channel} = fields)
       when is_binary(sub) and byte_size(sub) > 0 do
    with true <- String.length(sub) <= @max_length,
         {:ok, name} <- optional_name(fields["name"]),
         {:ok, session} <- session_claims(fields) do
      claims =
        %{
          sub: sub,
          exp: fields["exp"],
          name: name,
          phone: normalise_phone(fields["phone"])
        }
        |> Map.merge(session)
        |> Map.reject(fn {_key, value} -> is_nil(value) end)

      {:ok, claims}
    else
      _invalid -> :error
    end
  end

  defp extract_claims(_fields), do: :error

  @spec session_claims(map()) :: {:ok, map()} | :error
  defp session_claims(%{"jti" => jti, "sst" => sst}) when is_binary(jti) and is_integer(sst),
    do: {:ok, %{session_id: jti, session_started_at: sst}}

  defp session_claims(fields)
       when not is_map_key(fields, "jti") and not is_map_key(fields, "sst"),
       do: {:ok, %{}}

  defp session_claims(_fields), do: :error

  @spec validate_session(claims(), integer()) :: :ok | :error
  defp validate_session(%{session_started_at: started_at}, now) do
    if started_at <= now + @leeway_seconds and now - started_at < @session_max_seconds,
      do: :ok,
      else: :error
  end

  defp validate_session(_claims, _now), do: :ok

  @spec optional_name(any()) :: {:ok, String.t() | nil} | :error
  defp optional_name(nil), do: {:ok, nil}

  defp optional_name(name) when is_binary(name),
    do: if(String.length(name) <= @max_length, do: {:ok, name}, else: :error)

  defp optional_name(_name), do: :error

  @spec normalise_phone(any()) :: String.t() | nil
  defp normalise_phone(phone) when is_binary(phone) do
    case Contacts.parse_phone_number(phone) do
      {:ok, normalised} -> normalised
      {:error, _reason} -> nil
    end
  end

  defp normalise_phone(_phone), do: nil
end
