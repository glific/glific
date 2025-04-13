defmodule Glific.Templates.TemplateWorker do
  @moduledoc """
  Using this module to bulk apply template to Gupshup
  """

  require Logger

  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    priority: 2

  alias Glific.Repo

  @doc """
  Creating new job for each template
  """
  @spec make_job(list(), non_neg_integer()) :: :ok
  def make_job(templates, organization_id) do
    templates
    |> Enum.each(fn {title, template} ->
      __MODULE__.new(%{template: template, title: title, organization_id: organization_id})
      |> Oban.insert()
    end)
  end

  @impl Oban.Worker
  @doc """
  Standard perform method to use Oban worker
  """
  @spec perform(Oban.Job.t()) :: :ok
  def perform(
        %Oban.Job{
          args: %{
            "title" => title,
            "organization_id" => organization_id,
            "template" => template
          }
        } = _job
      ) do
    Repo.put_process_state(organization_id)
    Logger.info("Applying template for org_id: #{organization_id} title: #{title}")

    process_template(template)
    |> Glific.Templates.create_session_template()

    :ok
  end

  defp process_template(template) do
    button_type = Glific.safe_string_to_atom(template["button_type"])
    type = Glific.safe_string_to_atom(template["type"])

    template
    |> Glific.atomize_keys()
    |> Map.put(:button_type, button_type)
    |> Map.put(:type, type)
  end
end
