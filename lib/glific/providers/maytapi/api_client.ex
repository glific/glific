defmodule Glific.Providers.Maytapi.ApiClient do
  @moduledoc """
  Https API client to interact with Maytapi
  """

  alias Glific.Partners

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
    do: get(url, headers: headers(token))

  @doc """
  Making Tesla post call and adding api key in header
  """
  @spec maytapi_post(String.t(), any(), String.t()) :: Tesla.Env.result()
  def maytapi_post(url, payload, token) do
    post(url, payload, headers: headers(token))
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
  Removes a member from given whatsapp group
  """
  @spec remove_group_member(non_neg_integer(), map(), non_neg_integer()) :: Tesla.Env.result()
  def remove_group_member(org_id, payload, phone_id) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      product_id = secrets["product_id"]
      token = secrets["token"]
      url = @maytapi_url <> "/#{product_id}/#{phone_id}/group/remove"
      maytapi_post(url, Jason.encode!(payload), token)
    end
  end

  @doc """
  Adds members to the given WhatsApp group. Same payload shape as
  `remove_group_member/3`: a `number` array of plain phone numbers.

  `payload` shape:
      %{conversation_id: "120363...@g.us", number: ["91xxxxxxxxxx", ...]}
  """
  @spec add_group_member(non_neg_integer(), map(), non_neg_integer()) :: Tesla.Env.result()
  def add_group_member(org_id, payload, phone_id) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      product_id = secrets["product_id"]
      token = secrets["token"]

      url = @maytapi_url <> "/#{product_id}/#{phone_id}/group/add"
      maytapi_post(url, Jason.encode!(payload), token)
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
  Creates a new WhatsApp group from one of the org's managed phones.

  `payload` shape (per Maytapi docs):
      %{name: "Group name", numbers: ["91xxxxxxxxxx", ...]}

  The calling `phone_id` becomes the group creator/admin on WhatsApp.
  """
  @spec create_group(non_neg_integer(), non_neg_integer(), map()) :: Tesla.Env.result()
  def create_group(org_id, phone_id, payload) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      product_id = secrets["product_id"]
      token = secrets["token"]

      url = @maytapi_url <> "/#{product_id}/#{phone_id}/createGroup"
      maytapi_post(url, Jason.encode!(payload), token)
    end
  end

  @doc """
  Renames a WhatsApp group (sets its "subject" in WhatsApp terms).

  `payload` shape:
      %{conversation_id: "120363...@g.us", subject: "New name"}
  """
  @spec set_group_subject(non_neg_integer(), non_neg_integer(), map()) :: Tesla.Env.result()
  def set_group_subject(org_id, phone_id, payload) do
    with {:ok, secrets} <- fetch_credentials(org_id) do
      product_id = secrets["product_id"]
      token = secrets["token"]

      url = @maytapi_url <> "/#{product_id}/#{phone_id}/setGroupSubject"
      maytapi_post(url, Jason.encode!(payload), token)
    end
  end

  @doc """
  Handles a Maytapi group-operation response.

  Maytapi answers HTTP 200 even on failure, with
  `%{"success" => false, "message" => "...", "code" => "..."}`, so a 2xx status
  alone is not enough — we decode the body and check `success`.

  Returns `:ok` on success, or `{:error, message}` with Maytapi's message (or a
  generic message for non-2xx / transport / unexpected responses).
  """
  @spec handle_maytapi_response(Tesla.Env.result()) :: :ok | {:error, String.t()}
  def handle_maytapi_response({:ok, %Tesla.Env{status: status, body: body}})
      when status in 200..299 do
    case Jason.decode(body) do
      {:ok, %{"success" => true}} -> :ok
      {:ok, %{"success" => false, "message" => message}} -> {:error, message}
      {:ok, %{"success" => false}} -> {:error, "Maytapi request failed"}
      _ -> {:error, "Unexpected Maytapi response"}
    end
  end

  def handle_maytapi_response({:ok, %Tesla.Env{body: body}}), do: {:error, inspect(body)}
  def handle_maytapi_response({:error, reason}), do: {:error, inspect(reason)}
end
