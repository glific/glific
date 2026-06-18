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
    do: client() |> Tesla.get(url, headers: headers(token)) |> log_on_failure(url)

  # Group operations (createGroup, group/add, group/remove, setGroupSubject)
  # trigger real WhatsApp actions on the device and can take well over the
  # Hackney default 5s recv_timeout. Bump the read timeout so these don't
  # time out before Maytapi responds.
  @post_recv_timeout 60_000

  @doc """
  Making Tesla post call and adding api key in header
  """
  @spec maytapi_post(String.t(), any(), String.t()) :: Tesla.Env.result()
  def maytapi_post(url, payload, token) do
    client()
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

  @doc """
  Renames a WhatsApp group (sets its "subject" in WhatsApp terms). Returns `:ok`
  or `{:error, message}`.

  `payload` shape:
      %{conversation_id: "120363...@g.us", subject: "New name"}
  """
  @spec set_group_subject(non_neg_integer(), non_neg_integer(), map()) ::
          :ok | {:error, String.t()}
  def set_group_subject(org_id, phone_id, payload) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      product_id = secrets["product_id"]
      token = secrets["token"]

      url = @maytapi_url <> "/#{product_id}/#{phone_id}/setGroupSubject"

      maytapi_post(url, Jason.encode!(payload), token)
      |> handle_maytapi_response()
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
      {:ok, %{"success" => false, "message" => message}} -> {:error, message}
      {:ok, %{"success" => false}} -> {:error, "Maytapi request failed"}
      _ -> {:error, "Unexpected Maytapi response"}
    end
  end

  defp handle_maytapi_response({:ok, %Tesla.Env{body: body}}, _type), do: {:error, inspect(body)}
  defp handle_maytapi_response({:error, reason}, _type), do: {:error, inspect(reason)}

  @spec client() :: Tesla.Client.t()
  defp client, do: Tesla.client(Glific.get_tesla_retry_middleware())

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
