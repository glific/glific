defmodule Glific.Contacts.Worker do
  @moduledoc """
  A worker to update contact status
  """

  use Oban.Worker,
    max_attempts: 1,
    priority: 0

  alias Glific.Contacts
  alias Glific.Repo

  import Ecto.Query, warn: false

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(_args) do
    update_contacts_status()
  end

  @doc false
  @spec update_contacts_status :: :ok
  defp update_contacts_status do
    t = DateTime.utc_now() |> DateTime.add(-24 * 60 * 60)

    contacts =
      Contacts.Contact
      |> where([c], c.last_message_at <= ^t)
      |> Repo.all()

    contacts
    |> Enum.each(fn contact ->
      new_status = Contacts.set_session_status(contact, :none)
      Contacts.update_contact(contact, %{provider_status: new_status})
    end)

    :ok
  end
end
