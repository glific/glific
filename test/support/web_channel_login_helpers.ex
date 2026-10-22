defmodule Glific.WebChannelLoginHelpers do
  @moduledoc """
  Mints the JWTs an NGO's backend would sign for a web channel login, for tests.
  """

  alias JOSE.{JWK, JWS, JWT}

  @doc """
  A valid login token's claims, issued `now` and good for ten minutes; `overrides` replace or add
  claims, and a nil value drops one.
  """
  @spec claims(map(), integer()) :: map()
  def claims(overrides \\ %{}, now \\ System.system_time(:second)) do
    %{"sub" => "ravi_12", "channel" => "web", "iat" => now, "exp" => now + 600}
    |> Map.merge(overrides)
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  @doc """
  Signs `claims` with `secret` using the given algorithm.
  """
  @spec sign(map(), String.t(), String.t()) :: String.t()
  def sign(claims, secret, algorithm \\ "HS256") do
    {_jws, token} =
      secret
      |> JWK.from_oct()
      |> JWT.sign(%{"alg" => algorithm}, claims)
      |> JWS.compact()

    token
  end
end
