defmodule GlificWeb.WebChannel.JwtToken do
  @moduledoc """
  Verifies the JWT an NGO's backend signs to authenticate one of its users on the web channel
  socket. A token may live at most 24 hours; an NGO may issue shorter ones.

  The token is signed (HS256, pinned: the token's own `alg` is never trusted) with any of the
  organization's JWT signature secrets, a list of at most two `%{"name" => ..., "secret" => ...}`
  under `jwt_signature_secrets` in its `web_channel` credential; entries past the second are ignored.
  Neither is "current" or "previous", so rotating is a matter of adding the new secret and later
  removing the old one. The organization is
  the request's, not the token's. Every way a token can be wrong gives the same `{:error, :invalid}`.

  A secret shorter than 32 characters is ignored, so a token can never verify against it.

  This is not `GlificWeb.WebChannel.Token`, which is the token Glific itself issues after a phone
  and one-time code login.
  """

  alias Glific.{Contacts, Partners}
  alias JOSE.{JWK, JWT}

  @algorithm "HS256"
  @channel "web"
  @max_lifetime_seconds 86_400
  @leeway_seconds 60
  @max_length 255
  @min_secret_length 32
  @max_secrets 2
  @provider_code "web_channel"

  @type claims :: %{
          required(:sub) => String.t(),
          required(:exp) => integer(),
          optional(:name) => String.t(),
          optional(:phone) => String.t()
        }

  @doc """
  The claims of a token signed with any of the organization's JWT signature secrets, if it is valid now.
  """
  @spec verify(non_neg_integer(), String.t() | nil, integer()) ::
          {:ok, claims()} | {:error, :invalid}
  def verify(organization_id, token, now \\ System.system_time(:second))

  def verify(organization_id, token, now) when is_binary(token) and token != "" do
    with [_ | _] = secrets <- jwt_signature_secrets(organization_id),
         {:ok, fields} <- verify_signature(secrets, token),
         :ok <- validate_timing(fields, now),
         {:ok, claims} <- extract_claims(fields) do
      {:ok, claims}
    else
      _invalid -> {:error, :invalid}
    end
  end

  def verify(_organization_id, _token, _now), do: {:error, :invalid}

  @spec jwt_signature_secrets(non_neg_integer()) :: [String.t()]
  defp jwt_signature_secrets(organization_id) do
    case Partners.organization(organization_id) do
      {:error, _reason} ->
        []

      organization ->
        secrets = get_in(organization.services, [@provider_code, :secrets]) || %{}

        (secrets["jwt_signature_secrets"] || secrets[:jwt_signature_secrets])
        |> List.wrap()
        |> Enum.take(@max_secrets)
        |> Enum.map(&secret_of/1)
        |> Enum.filter(&(is_binary(&1) and String.length(&1) >= @min_secret_length))
    end
  end

  @spec secret_of(any()) :: String.t() | nil
  defp secret_of(%{"secret" => secret}), do: secret
  defp secret_of(%{secret: secret}), do: secret
  defp secret_of(_entry), do: nil

  @spec verify_signature([String.t()], String.t()) :: {:ok, map()} | :error
  defp verify_signature(secrets, token) do
    Enum.find_value(secrets, :error, fn secret ->
      case JWT.verify_strict(JWK.from_oct(secret), [@algorithm], token) do
        {true, %JWT{fields: fields}, _jws} -> {:ok, fields}
        _unverified -> nil
      end
    end)
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
         {:ok, name} <- optional_name(fields["name"]) do
      claims =
        %{
          sub: sub,
          exp: fields["exp"],
          name: name,
          phone: normalise_phone(fields["phone"])
        }
        |> Map.reject(fn {_key, value} -> is_nil(value) end)

      {:ok, claims}
    else
      _invalid -> :error
    end
  end

  defp extract_claims(_fields), do: :error

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
