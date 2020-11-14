defmodule GlificWeb.Misc.BodyReader do
  @moduledoc """
  Code to cache the raw body in a conn variable before being
  processed by Phoenix. Used to validate the signature
  """

  @doc """
  Store the raw body in the conn assigns array
  """
  @spec cache_raw_body(Conn.t(), Keyword.t()) :: tuple()
  def cache_raw_body(conn, opts) do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn, opts) do
      conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])

      {:ok, body, conn}
    end
  end
end
