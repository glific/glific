defmodule Glific.Providers.ContactBehaviour do
  @moduledoc """
  The contact behaviour which all the providers needs to implement for communication
  """

  @callback optin_contact(message :: Glific.Messages.Message.t()) ::
              {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}

end
