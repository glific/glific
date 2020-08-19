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
    update_contact_status()
  end

  @doc false
  @spec update_contact_status :: :ok
  defp update_contact_status do
    t = Glific.go_back_time(24)

    contacts =
      Contacts.Contact
      |> where([c], c.last_message_at <= ^t)
      |> Repo.all()

    contacts
    |> Enum.each(fn contact ->
      Contacts.set_session_status(contact, :none)
    end)

    :ok
  end
end
