defmodule Glific.Providers.Maytapi.ApiClient do
  @moduledoc """
  Https API client to interact with Maytapi
  """

  alias Glific.Partners
  alias Plug.Conn.Query
  import Ecto.Query

  @maytapi_url "https://api.maytapi.com/api"

  use Tesla

  alias Glific.{
    WAGroup.WAManagedPhone,
    Repo,
    Notifications
  }

  plug(Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1
  )

  @spec headers(String.t()) :: list()
  defp headers(token),
    do: [
      {"accept", "application/json"},
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
      maytapi_post(url, payload, token)
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
      maytapi_post(url, payload, token)
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
      maytapi_post(url, payload, token)
    end
  end

  @doc """
  add the phone status
  """
  @spec status(String.t(), non_neg_integer()) :: {:ok, WAManagedPhone} | {:error, String.t()}
  def status(new_status, phone_id) do
    organization_id = Repo.get_organization_id()

    phone =
      from(p in WAManagedPhone,
        where: p.phone_id == ^phone_id
      )
      |> Repo.one()

    case phone do
      nil ->
        {:error, "Phone ID not found"}

      _phone ->
        case phone
             |> WAManagedPhone.changeset(%{status: new_status})
             |> Repo.update() do
          {:ok, wa_managed_phone} ->
            if new_status != "active" do
              Notifications.create_notification(%{
                category: "WhatsApp Groups",
                message:
                  "Cannot send messages. WhatsApp phone #{wa_managed_phone.phone} is not connected with Maytapi. Current status: #{wa_managed_phone.status}",
                severity: Notifications.types().critical,
                organization_id: organization_id,
                entity: %{
                  phone: wa_managed_phone.phone,
                  status: new_status
                }
              })
            end

            {:ok, wa_managed_phone}

          {:error, _changeset} ->
            {:error, "Failed to update status"}
        end
    end
  end
end
