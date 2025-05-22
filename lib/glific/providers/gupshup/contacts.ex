defmodule Glific.Providers.GupshupContacts do
  @moduledoc """
  Contacts API layer between application and Gupshup
  """

  use Publicist

  @behaviour Glific.Providers.ContactBehaviour

  use Gettext, backend: GlificWeb.Gettext

  alias Glific.{
    Contacts,
    Contacts.Contact
  }

  @doc """
    Update a contact phone as opted in
  """

  @spec optin_contact(map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()} | {:error, list()}
  def optin_contact(%{organization_id: organization_id} = attrs) do
    Contacts.contact_opted_in(
      attrs,
      organization_id,
      attrs[:optin_time] || DateTime.utc_now(),
      method: attrs[:method] || "BSP"
    )
  end

  @doc """
  Perform the gupshup API call and parse the results for downstream functions.
  We need to think about if we want to add him to behaviour
  """
  @spec validate_opted_in_contacts(Tesla.Env.result()) ::
          {:ok, list()} | {:error, String.t(), atom()}
  def validate_opted_in_contacts(result) do
    case result do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, response_data} = Jason.decode(body)

        if response_data["status"] == "error" do
          {:error, dgettext("errors", "Message: %{message}", message: response_data["message"]),
           :app_name}
        else
          users = response_data["users"]
          {:ok, users}
        end

      {:ok, %Tesla.Env{status: status}} when status in 400..499 ->
        {:error, dgettext("errors", "Invalid BSP API key"), :api_key}

      {:error, %Tesla.Error{reason: reason}} ->
        {:error, dgettext("errors", "Reason: %{reason}", reason: reason), :app_name}
    end
  end
end
