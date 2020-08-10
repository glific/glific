defmodule Glific.Contacts.Worker do
  @moduledoc """
  A worker to update contact status
  """

  use Oban.Worker,
    max_attempts: 1,
    priority: 0

  alias Glific.Contacts

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
    Contacts.list_contacts(%{filter: %{provider_status: :session_and_hsm}})
    |> Enum.each(fn contact ->
      with true <- Timex.diff(DateTime.utc_now(), contact.last_message_at, :hours) > 24 do
        Contacts.update_contact(contact, %{provider_status: :none})
      end
    end)

    :ok
  end
end
