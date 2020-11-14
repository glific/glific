defmodule GlificWeb.Misc.HTTPSignature do
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    with {:ok, header} <- signature_header(conn),
         {:ok, body} <- raw_body(conn),
           :ok <- verify(header, body, "secret", opts) do
      conn
    else
      {:error, error} ->
        conn
        |> put_status(400)
        |> json(%{
            "error" => %{"status" => "400", "title" => "HTTP Signature is invalid: #{error}"}
                })
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

  def verify(header, payload, secret, opts \\ []) do
    with {:ok, timestamp, hash} <- parse(header, @schema) do
      current_timestamp = System.system_time(:second)

      cond do
        timestamp + @valid_period_in_seconds < current_timestamp ->
          {:error, "signature is too old"}

        not Plug.Crypto.secure_compare(hash, hash(timestamp, payload, secret)) ->
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
