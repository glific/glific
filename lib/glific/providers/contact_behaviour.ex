defmodule Glific.Providers.ContactBehaviour do
  @moduledoc """
  The contact behaviour which all the providers needs to implement for communication
  """

  alias Glific.Contacts.Contact

  @callback optin_contact(attrs :: map()) ::
              {:ok, Contact.t()} | {:error, Ecto.Changeset.t()} | {:error, list()}

  @callback fetch_opted_in_contacts(attrs :: map()) :: :ok | {:error, String.t()}
end
