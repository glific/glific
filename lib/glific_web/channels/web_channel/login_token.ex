defmodule GlificWeb.WebChannel.LoginToken do
  @moduledoc """
  Verifies the JWT an NGO's backend signs to authenticate one of its users on the web channel
  socket, or to provision a contact for one. A token may live at most 24 hours; an NGO may issue
  shorter ones.

  The token is signed (HS256, pinned: the token's own `alg` is never trusted) with either of the
  organization's two login secrets (`login_key_1_secret`, `login_key_2_secret`); neither is
  "current" or "previous", so rotating is a matter of filling the empty slot and later clearing the
  old one. Both live in the organization's `web_channel` credential, so the organization is the
  request's, not the token's. Every way a token can be wrong gives the same `{:error, :invalid}`.

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
  @provider_code "web_channel"
  @secret_fields [:login_key_1_secret, :login_key_2_secret]

  @type claims :: %{
          required(:sub) => String.t(),
          required(:exp) => integer(),
          optional(:name) => String.t(),
          optional(:phone) => String.t(),
          optional(:contact_id) => integer()
        }

  @doc """
  The claims of a token signed with either of the organization's login secrets, if it is valid now.
  """
  @spec verify(non_neg_integer(), String.t() | nil, integer()) ::
          {:ok, claims()} | {:error, :invalid}
  def verify(organization_id, token, now \\ System.system_time(:second))

  def verify(organization_id, token, now) when is_binary(token) and token != "" do
    with [_ | _] = secrets <- login_secrets(organization_id),
         {:ok, fields} <- verify_signature(secrets, token),
         :ok <- validate_timing(fields, now),
         {:ok, claims} <- extract_claims(fields) do
      {:ok, claims}
    else
      _invalid -> {:error, :invalid}
    end
  end

  def verify(_organization_id, _token, _now), do: {:error, :invalid}

  @spec login_secrets(non_neg_integer()) :: [String.t()]
  defp login_secrets(organization_id) do
    case Partners.organization(organization_id) do
      {:error, _reason} ->
        []

      organization ->
        secrets = get_in(organization.services, [@provider_code, :secrets]) || %{}

        @secret_fields
        |> Enum.map(&(secrets[Atom.to_string(&1)] || secrets[&1]))
        |> Enum.filter(&(is_binary(&1) and &1 != ""))
    end
  end

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
         {:ok, name} <- optional_name(fields["name"]),
         {:ok, contact_id} <- optional_contact_id(fields["contact_id"]) do
      claims =
        %{
          sub: sub,
          exp: fields["exp"],
          name: name,
          contact_id: contact_id,
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

  @spec optional_contact_id(any()) :: {:ok, integer() | nil} | :error
  defp optional_contact_id(nil), do: {:ok, nil}
  defp optional_contact_id(contact_id) when is_integer(contact_id), do: {:ok, contact_id}
  defp optional_contact_id(_contact_id), do: :error

  @spec normalise_phone(any()) :: String.t() | nil
  defp normalise_phone(phone) when is_binary(phone) do
    case Contacts.parse_phone_number(phone) do
      {:ok, normalised} -> normalised
      {:error, _reason} -> nil
    end
  end

  defp normalise_phone(_phone), do: nil
end
