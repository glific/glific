defmodule Glific.Contacts.Worker do
  @moduledoc """
  A worker to update contact status
  """

  use Oban.Worker,
    max_attempts: 1,
    priority: 0

  alias Glific.{
    Contacts,
    Partners,
    Repo
  }

  import Ecto.Query, warn: false

  @doc """
  Standard perform method to use Oban worker
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(_args) do
    # We need to do this for all the active organizations
    Partners.active_organizations()
    |> Enum.each(fn {id, _name} -> update_contact_status(id) end)
  end

  @doc false
  @spec update_contact_status(non_neg_integer) :: :ok
  defp update_contact_status(organization_id) do
    t = Glific.go_back_time(24)

    contacts =
      Contacts.Contact
      |> where([c], c.last_message_at <= ^t)
      |> where([c], c.organization_id == ^organization_id)
      |> Repo.all()

    contacts
    |> Enum.each(fn contact ->
      Contacts.set_session_status(contact, :none)
    end)

    :ok
  end
end
