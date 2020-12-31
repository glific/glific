defmodule Glific.Providers.ContactBehaviour do
  @moduledoc """
  The contact behaviour which all the providers needs to implement for communication
  """

  alias Glific.Contacts.Contact

  @callback optin_contact(attrs :: map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
end
