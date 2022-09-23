defmodule Glific.Contacts.ImportWorker do
  @moduledoc """
   This module we are using to import a bunch of contacts
  """

  use Oban.Worker,
    queue: :import_contacts,
    max_attempts: 1,
    priority: 1

  alias Glific.Contacts.Import

  @impl Oban.Worker

  @doc """
    This is a method to perform oban worker
  """
  @spec perform(Oban.Job.t()) :: tuple()
  def perform(%Oban.Job{
        args: %{
          "organization_id" => organization_id,
          "params" => %{group_label: group_label, user: user},
          "opts" => opts
        }
      }),
      do:
        Import.import_contacts(organization_id, %{group_label: group_label, user: user},
          opts: opts
        )
end
