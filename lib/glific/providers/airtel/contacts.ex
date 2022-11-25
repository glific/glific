defmodule Glific.Providers.AirtelContacts do
  @moduledoc """
  Contacts API layer between application and Airtel
  """

  @behaviour Glific.Providers.ContactBehaviour

  use Publicist

  alias Glific.Contacts
  alias Glific.Contacts.Contact

  @doc """
    Update a contact phone as opted in
  """

  @spec optin_contact(map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()} | {:error, list()}
  def optin_contact(%{organization_id: _organization_id} = _attrs) do
    {:ok, Contacts.get_contact!(1)}
  end

  @doc """
  Fetch opted in contacts data from providers server
  """
  @spec fetch_opted_in_contacts(map()) :: :ok | {:error, String.t()}
  def fetch_opted_in_contacts(_attrs) do
    :ok
  end

  @doc """
  Perform the airtel API call and parse the results for downstream functions
  """
  @spec validate_opted_in_contacts(Tesla.Env.result()) :: {:ok, list()} | {:error, String.t()}
  def validate_opted_in_contacts(_result) do
    {:ok, []}
  end
end
