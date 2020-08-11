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
  @spec update_contacts_status() :: :ok
  defp update_contacts_status() do
    t = DateTime.utc_now() |> DateTime.add(-24 * 60 * 60)

    contacts =
      Contacts.Contact
      |> where([c], c.last_message_at <= ^t)
      |> where([c], c.provider_status == "session" or c.provider_status == "session_and_hsm")
      |> Repo.all()

    contacts
    |> Enum.each(fn contact ->
      case contact.provider_status do
        :session_and_hsm ->
          Contacts.update_contact(contact, %{provider_status: :hsm})

        :session ->
          Contacts.update_contact(contact, %{provider_status: :none})
      end
    end)

    :ok
  end
end
