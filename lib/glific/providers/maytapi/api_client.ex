defmodule Glific.Providers.Maytapi.ApiClient do
  @moduledoc """
  Https API client to interact with Maytapi
  """

  alias Glific.{Partners, SafeLog}

  @maytapi_url "https://api.maytapi.com/api"

  use Tesla

  @spec headers(String.t()) :: list()
  defp headers(token),
    do: [
      {"accept", "application/json"},
      {"Content-Type", "application/json"},
      {"x-maytapi-key", token}
    ]

  @doc """
  Making Tesla get call and adding api key in header
  """
  @spec maytapi_get(String.t(), String.t()) :: Tesla.Env.result()
  def maytapi_get(url, token),
    do:
      :read
      |> client()
      |> Tesla.get(url, headers: headers(token))
      |> log_on_failure(url)

  # Group operations (createGroup, group/add, group/remove)
  # trigger real WhatsApp actions on the device and can take well over the
  # Hackney default 5s recv_timeout. Bump the read timeout so these don't
  # time out before Maytapi responds.
  @post_recv_timeout 60_000

  # Maytapi's code for "the WhatsApp instance's lib isn't loaded yet" — a
  # transient state for a few seconds after a restart/reconnect. Maytapi returns
  # it as HTTP 200 with `success: false`, so the Tesla retry below inspects the
  # body (not just the status) to catch and retry it.
  @instance_not_ready_code "W05"

  # Shown to the user when Maytapi fails with something we don't have a specific
  # message for. The raw detail is always logged separately.
  @generic_error "WhatsApp couldn't complete this action right now. Please try again in a moment."

  @doc """
  Making Tesla post call and adding api key in header
  """
  @spec maytapi_post(String.t(), any(), String.t()) :: Tesla.Env.result()
  def maytapi_post(url, payload, token) do
    client(:write)
    |> Tesla.post(url, payload,
      headers: headers(token),
      opts: [adapter: [recv_timeout: @post_recv_timeout]]
    )
    |> log_on_failure(url)
  end

  @doc false
  @spec fetch_credentials(non_neg_integer) :: nil | {:ok, any} | {:error, any}
  def fetch_credentials(organization_id) do
    organization = Partners.organization(organization_id)

    organization.services["maytapi"]
    |> case do
      nil ->
        {:error, "Maytapi is not active"}

      credentials ->
        merged_credentials = Map.merge(credentials.secrets, credentials.keys)
        {:ok, merged_credentials}
    end
  end

  @doc """
  Fetches group using Maytapi API and sync it in Glific

  ## Examples

      iex> list_wa_groups()
      [%Group{}, ...]

  """
  @spec list_wa_groups(non_neg_integer(), non_neg_integer()) :: Tesla.Env.result()
  def list_wa_groups(org_id, phone_id) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      product_id = secrets["product_id"]
      token = secrets["token"]

      url = @maytapi_url <> "/#{product_id}/#{phone_id}/getGroups"
      maytapi_get(url, token)
    end
  end

  @doc """
  Fetches phone numbers linked to Maytapi account and sync it in Glific
  """
  @spec list_wa_managed_phones(non_neg_integer()) :: Tesla.Env.result()
  def list_wa_managed_phones(org_id) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      product_id = secrets["product_id"]
      token = secrets["token"]

      url = @maytapi_url <> "/#{product_id}/listPhones"

      maytapi_get(url, token)
    end
  end

  @doc """
  Fetches the current screen for a phone. When the phone is on the WhatsApp login
  screen (status `qr-screen`), this is the QR image to rescan — the surface we
  expose so admins can reconnect a disconnected phone from Glific.

  Maytapi returns the screen as raw PNG bytes, so this returns `{:ok, data_url}`
  (a `data:image/png;base64,...` string the frontend can render) or
  `{:error, message}`; the raw HTTP/Tesla layer is handled here.
  """
  @spec fetch_phone_screen(non_neg_integer(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, String.t()}
  def fetch_phone_screen(org_id, phone_id) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      product_id = secrets["product_id"]
      token = secrets["token"]

      url = @maytapi_url <> "/#{product_id}/#{phone_id}/screen"

      url
      |> maytapi_get(token)
      |> handle_screen_response()
    end
  end

  @doc """
  Logs a phone out of its WhatsApp session so Maytapi shows a fresh QR to relink.
  Returns `:ok` or `{:error, message}`.
  """
  @spec logout_phone(non_neg_integer(), non_neg_integer()) :: :ok | {:error, String.t()}
  def logout_phone(org_id, phone_id) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      product_id = secrets["product_id"]
      token = secrets["token"]

      url = @maytapi_url <> "/#{product_id}/#{phone_id}/logout"

      url
      |> maytapi_post(Jason.encode!(%{}), token)
      |> handle_maytapi_response()
    end
  end

  # Maytapi's `screen` endpoint returns the raw PNG bytes of the phone's current
  # screen (the QR image when it's on the login screen) on success. But like the
  # rest of Maytapi it signals real errors as HTTP 200 + {"success": false} JSON,
  # so only Base64 a body that actually is a PNG — otherwise surface the error
  # rather than handing back a bogus data-url QR.
  @spec handle_screen_response(Tesla.Env.result()) :: {:ok, String.t()} | {:error, String.t()}
  defp handle_screen_response({:ok, %Tesla.Env{status: status, body: body}})
       when status in 200..299 do
    if png?(body) do
      {:ok, "data:image/png;base64," <> Base.encode64(body)}
    else
      screen_error(body)
    end
  end

  defp handle_screen_response({:ok, %Tesla.Env{body: body}}) do
    Glific.log_error("Maytapi screen non-2xx response: #{SafeLog.safe_inspect(body)}")
    {:error, @generic_error}
  end

  defp handle_screen_response({:error, reason}) do
    Glific.log_error("Maytapi screen request error: #{SafeLog.safe_inspect(reason)}")
    {:error, @generic_error}
  end

  @spec png?(any()) :: boolean()
  defp png?(<<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>), do: true
  defp png?(_), do: false

  # A 200 that isn't a PNG is Maytapi's JSON error shape — surface its message.
  @spec screen_error(binary()) :: {:error, String.t()}
  defp screen_error(body) do
    case Jason.decode(body) do
      {:ok, %{"message" => message}} when is_binary(message) -> {:error, message}
      _ -> {:error, @generic_error}
    end
  end

  @doc """
  Sending message to contact
  """
  @spec send_message(non_neg_integer(), map(), non_neg_integer()) :: Tesla.Env.result()
  def send_message(org_id, payload, phone_id) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      product_id = secrets["product_id"]
      token = secrets["token"]

      url = @maytapi_url <> "/#{product_id}/#{phone_id}/sendMessage"
      Glific.Metrics.increment("Sent WAGroup msg")
      maytapi_post(url, Jason.encode!(payload), token)
    end
  end

  @doc """
  Removes a member from given whatsapp group. Returns `:ok` or `{:error, message}`.
  """
  @spec remove_group_member(non_neg_integer(), map(), non_neg_integer()) ::
          :ok | {:error, String.t()}
  def remove_group_member(org_id, payload, phone_id) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      product_id = secrets["product_id"]
      token = secrets["token"]
      url = @maytapi_url <> "/#{product_id}/#{phone_id}/group/remove"

      maytapi_post(url, Jason.encode!(payload), token)
      |> handle_maytapi_response()
    end
  end

  @doc """
  Adds members to the given WhatsApp group. Same payload shape as
  `remove_group_member/3`: a `number` array of plain phone numbers. Returns `:ok`
  or `{:error, message}`.

  `payload` shape:
      %{conversation_id: "120363...@g.us", number: ["91xxxxxxxxxx", ...]}
  """
  @spec add_group_member(non_neg_integer(), map(), non_neg_integer()) ::
          :ok | {:error, String.t()}
  def add_group_member(org_id, payload, phone_id) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      product_id = secrets["product_id"]
      token = secrets["token"]

      url = @maytapi_url <> "/#{product_id}/#{phone_id}/group/add"

      maytapi_post(url, Jason.encode!(payload), token)
      |> handle_maytapi_response()
    end
  end

  @doc """
  Sets the maytapi webhook for the org
  """
  @spec set_webhook(non_neg_integer(), map()) :: Tesla.Env.result()
  def set_webhook(org_id, payload) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      product_id = secrets["product_id"]
      token = secrets["token"]

      url = @maytapi_url <> "/#{product_id}/setWebhook"
      maytapi_post(url, Jason.encode!(payload), token)
    end
  end

  @doc """
  Creates a new WhatsApp group from one of the org's managed phones and returns
  the new group's `bsp_id` plus the participant/admin lists Maytapi echoes back.

  `payload` shape (per Maytapi docs):
      %{name: "Group name", numbers: ["91xxxxxxxxxx", ...]}

  The calling `phone_id` becomes the group creator/admin on WhatsApp.
  """
  @spec create_group(non_neg_integer(), non_neg_integer(), map()) ::
          {:ok, %{bsp_id: String.t(), participants: [String.t()], admins: [String.t()]}}
          | {:error, String.t()}
  def create_group(org_id, phone_id, payload) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      product_id = secrets["product_id"]
      token = secrets["token"]

      url = @maytapi_url <> "/#{product_id}/#{phone_id}/createGroup"

      maytapi_post(url, Jason.encode!(payload), token)
      |> handle_maytapi_response(:create)
    end
  end

  # Handles any Maytapi response. Maytapi answers HTTP 200 even on failure, with
  # `%{"success" => false, "message" => "...", "code" => "..."}`, so a 2xx status
  # alone is not enough — we decode the body and check `success`. The `:create`
  # clause extracts the new group's data; the default clause just reports `:ok`.
  # Non-2xx / transport / unexpected → `{:error, message}`.
  @spec handle_maytapi_response(Tesla.Env.result(), :create | :default) ::
          :ok | {:ok, map()} | {:error, String.t()}
  defp handle_maytapi_response(response, type \\ :default)

  defp handle_maytapi_response({:ok, %Tesla.Env{status: status, body: body}}, :create)
       when status in 200..299 do
    case Jason.decode(body) do
      {:ok, %{"success" => true, "data" => %{"id" => id} = data}} when is_binary(id) ->
        {:ok,
         %{bsp_id: id, participants: data["participants"] || [], admins: data["admins"] || []}}

      {:ok, %{"success" => false, "message" => message}} ->
        {:error, message}

      _ ->
        {:error, "Unexpected Maytapi create group response"}
    end
  end

  defp handle_maytapi_response({:ok, %Tesla.Env{status: status, body: body}}, _type)
       when status in 200..299 do
    case Jason.decode(body) do
      {:ok, %{"success" => true}} -> :ok
      {:ok, %{"success" => false} = failure} -> {:error, user_facing_error(failure)}
      _ -> {:error, @generic_error}
    end
  end

  defp handle_maytapi_response({:ok, %Tesla.Env{body: body}}, _type) do
    Glific.log_error("Maytapi non-2xx response: #{SafeLog.safe_inspect(body)}")
    {:error, @generic_error}
  end

  defp handle_maytapi_response({:error, reason}, _type) do
    Glific.log_error("Maytapi request error: #{SafeLog.safe_inspect(reason)}")
    {:error, @generic_error}
  end

  @spec user_facing_error(map()) :: String.t()
  defp user_facing_error(failure) do
    Glific.log_error("Maytapi request failed: #{SafeLog.safe_inspect(failure)}")

    cond do
      failure["code"] == @instance_not_ready_code ->
        "This WhatsApp number isn't connected right now. Check its status or reconnect it, then try again."

      is_binary(failure["message"]) ->
        map_maytapi_message(failure["message"])

      true ->
        @generic_error
    end
  end

  @spec map_maytapi_message(String.t()) :: String.t()
  defp map_maytapi_message(message) do
    cond do
      String.contains?(message, "NOT_A_PARTICIPANT") ->
        "That contact isn't a participant in this WhatsApp group."

      String.contains?(String.upcase(message), "NOT_ON_WHATSAPP") ->
        "This number isn't on WhatsApp."

      true ->
        @generic_error
    end
  end

  @retry_delay 2_000
  @retry_max_delay 8_000
  @retry_max_retries 3

  # Build a Maytapi client whose retry policy the caller chooses explicitly.
  # `:read` (idempotent GETs) retries the library's standard transient failures
  # (5xx/timeout) plus W05. `:write` (non-idempotent POSTs — createGroup,
  # group/add, group/remove, sendMessage) retries only W05, which guarantees the
  # action never started; a 5xx/timeout retry could otherwise duplicate the write.
  @spec client(:read | :write) :: Tesla.Client.t()
  defp client(retry_mode) do
    [{Tesla.Middleware.Retry, base_opts}] =
      Glific.get_tesla_retry_middleware(%{delay: @retry_delay, max_retries: @retry_max_retries})

    standard_retry? = Keyword.fetch!(base_opts, :should_retry)

    opts =
      base_opts
      |> Keyword.merge(max_delay: @retry_max_delay, jitter_factor: 0.2)
      |> Keyword.put(:should_retry, should_retry(retry_mode, standard_retry?))

    Tesla.client([{Tesla.Middleware.Retry, opts}])
  end

  @spec should_retry(:read | :write, function()) :: function()
  defp should_retry(:read, standard_retry?) do
    fn result, env, opts ->
      standard_retry?.(result, env, opts) or maytapi_lib_not_loaded?(result)
    end
  end

  defp should_retry(:write, _standard_retry?) do
    fn result, _env, _opts -> maytapi_lib_not_loaded?(result) end
  end

  @spec maytapi_lib_not_loaded?(Tesla.Env.result()) :: boolean()
  defp maytapi_lib_not_loaded?({:ok, %{body: body}}), do: instance_not_ready?(body)
  defp maytapi_lib_not_loaded?(_result), do: false

  @spec instance_not_ready?(any()) :: boolean()
  defp instance_not_ready?(body) when is_binary(body),
    do: match?({:ok, %{"code" => @instance_not_ready_code}}, Jason.decode(body))

  defp instance_not_ready?(_body), do: false

  @spec log_on_failure(Tesla.Env.result(), String.t()) :: Tesla.Env.result()
  defp log_on_failure({:ok, %Tesla.Env{status: status}} = result, _url)
       when status in 200..299,
       do: result

  defp log_on_failure({:ok, env} = result, url) do
    Glific.log_error("Maytapi request failed (#{url}): #{SafeLog.safe_inspect(env)}")
    result
  end

  defp log_on_failure({:error, reason} = result, url) do
    Glific.log_error("Maytapi request failed (#{url}): #{SafeLog.safe_inspect(reason)}")
    result
  end
end
