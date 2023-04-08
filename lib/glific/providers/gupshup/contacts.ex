defmodule Glific.Providers.GupshupContacts do
  @moduledoc """
  Contacts API layer between application and Gupshup
  """

  use Publicist

  @behaviour Glific.Providers.ContactBehaviour

  import GlificWeb.Gettext

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Providers.Gupshup.ApiClient,
    Providers.Gupshup.ContactWorker
  }

  @doc """
    Update a contact phone as opted in
  """

  @spec optin_contact(map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()} | {:error, list()}
  def optin_contact(%{organization_id: organization_id} = attrs) do
    ApiClient.optin_contact(organization_id, %{user: attrs.phone})
    |> case do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 ->
        Contacts.contact_opted_in(
          attrs,
          organization_id,
          attrs[:optin_time] || DateTime.utc_now(),
          method: attrs[:method] || "BSP"
        )

      _ ->
        {:error, ["gupshup", "couldn't connect"]}
    end
  end

  @per_page_limit 5000
  @doc """
  Fetch opted in contacts data from providers server
  """
  @spec fetch_opted_in_contacts(map()) :: :ok | {:error, String.t()}
  def fetch_opted_in_contacts(attrs) do
    do_fetch_opted_in_contacts(attrs.organization_id, @per_page_limit, 1)
  end

  @spec do_fetch_opted_in_contacts(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, String.t()}
  defp do_fetch_opted_in_contacts(org_id, @per_page_limit, page) do
    ApiClient.fetch_opted_in_contacts(org_id, page)
    |> validate_opted_in_contacts()
    |> case do
      {:ok, users} ->
        Enum.chunk_every(users, 1000)
        |> Enum.each(fn users ->
          ContactWorker.make_job(users, org_id)
        end)

        do_fetch_opted_in_contacts(org_id, length(users), page + 1)

      error ->
        error
    end
  end

  defp do_fetch_opted_in_contacts(_org_id, _user_count, _page), do: :ok

  @doc """
  Perform the gupshup API call and parse the results for downstream functions.
  We need to think about if we want to add him to behaviour
  """
  @spec validate_opted_in_contacts(Tesla.Env.result()) :: {:ok, list()} | {:error, String.t()}
  def validate_opted_in_contacts(result) do
    case result do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, response_data} = Jason.decode(body)

        if response_data["status"] == "error" do
          {:error, dgettext("errors", "Message: %{message}", message: response_data["message"])}
        else
          users = response_data["users"]
          {:ok, users}
        end

      {:ok, %Tesla.Env{status: status}} when status in 400..499 ->
        {:error, dgettext("errors", "Invalid BSP API key")}

      {:error, %Tesla.Error{reason: reason}} ->
        {:error, dgettext("errors", "Reason: %{reason}", reason: reason)}
    end
  end
end
