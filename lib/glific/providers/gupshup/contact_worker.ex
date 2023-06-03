defmodule Glific.Providers.Gupshup.ContactWorker do
  @moduledoc """
  Using this module to bulk apply template to Gupshup
  """

  require Logger

  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    priority: 2

  alias Glific.{
    Contacts,
    Partners,
    Partners.Organization,
    Repo
  }

  @days_shift -14

  @doc """
  Creating new job for each template
  """
  @spec make_job(list(), non_neg_integer()) :: :ok
  def make_job(users, organization_id) do
    __MODULE__.new(%{users: users, organization_id: organization_id})
    |> Oban.insert()

    :ok
  end

  @impl Oban.Worker
  @doc """
  Standard perform method to use Oban worker
  """
  @spec perform(Oban.Job.t()) :: :ok
  def perform(
        %Oban.Job{
          args: %{
            "users" => users,
            "organization_id" => organization_id
          }
        } = _job
      ) do
    Repo.put_process_state(organization_id)
    organization = Partners.organization(organization_id)
    Enum.each(users, &update_contacts(&1, organization))
  end

  @spec update_contacts(map() | nil, Organization.t() | nil) :: :ok | any()
  defp update_contacts(user, organization) do
    if user["optinStatus"] == "OPT_IN" do
      # handle scenario when contact has not sent a message yet
      last_message_at = last_message_at(user["lastMessageTimeStamp"])

      {:ok, optin_time} = DateTime.from_unix(user["optinTimeStamp"], :millisecond)

      phone = user["countryCode"] <> user["phoneCode"]

      Contacts.upsert(%{
        phone: phone,
        last_message_at: last_message_at,
        optin_time: optin_time |> DateTime.truncate(:second),
        optin_status: true,
        optin_method: user["optinSource"],
        bsp_status: check_bsp_status(last_message_at),
        organization_id: organization.id,
        language_id: organization.default_language_id,
        last_communication_at: last_message_at
      })
    end
  end

  @spec last_message_at(non_neg_integer()) :: DateTime.t()
  defp last_message_at(0) do
    Timex.shift(DateTime.utc_now(), days: @days_shift)
  end

  defp last_message_at(time) do
    DateTime.from_unix(time, :millisecond)
    |> elem(1)
    |> DateTime.truncate(:second)
  end

  @spec check_bsp_status(DateTime.t()) :: atom()
  defp check_bsp_status(last_message_at) do
    if Timex.diff(DateTime.utc_now(), last_message_at, :hours) < Glific.session_window_time(),
      do: :session_and_hsm,
      else: :hsm
  end
end
