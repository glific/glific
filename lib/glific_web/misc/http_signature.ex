defmodule GlificWeb.Misc.HTTPSignature do
  @moduledoc """
  Verify that the signature matches from the incoming webhook
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  @doc false
  def init(opts), do: opts

  @impl true
  @doc false
  def call(conn, _opts) do
    with header <- get_req_header(conn, "X-Glific-Signature"),
         {:ok, body} <- raw_body(conn),
         :ok <- verify(header, body, conn) do
      conn
    else
      _ ->
        conn
        |> send_resp(
          400,
          Jason.encode(%{
            "error" => %{"status" => "400", "title" => "HTTP Signature is invalid:"}
          })
        )
        |> halt()
    end
  end

  defp raw_body(conn) do
    case conn do
      %Plug.Conn{assigns: %{raw_body: raw_body}} ->
        # We cached as iodata, so we need to transform here.
        {:ok, IO.iodata_to_binary(raw_body)}

      _ ->
        raise "raw body is not present"
    end
  end

  @valid_period_in_seconds 60
  @schema "v1"

  defp verify(header, payload, conn) do
    with {:ok, timestamp, hash} <- parse(header, @schema) do
      current_timestamp = System.system_time(:second)

      cond do
        timestamp + @valid_period_in_seconds < current_timestamp ->
          {:error, "signature is too old"}

        not Plug.Crypto.secure_compare(
          hash,
          Glific.signature(conn.assigns[:organization_id], payload, timestamp)
        ) ->
          {:error, "signature is incorrect"}

        true ->
          :ok
      end
    end
  end

  defp parse(signature, schema) do
    parsed =
      for pair <- String.split(signature, ","),
          destructure([key, value], String.split(pair, "=", parts: 2)),
          do: {key, value},
          into: %{}

    with %{"t" => timestamp, ^schema => hash} <- parsed,
         {timestamp, ""} <- Integer.parse(timestamp) do
      {:ok, timestamp, hash}
    else
      _ -> {:error, "signature is in a wrong format or is missing #{schema} schema"}
    end
  end
end
