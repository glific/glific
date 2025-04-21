defmodule Glific.Templates.TemplateWorker do
  @moduledoc """
  Using this module to bulk apply template to Gupshup
  """

  require Logger
  alias Glific.{Templates, Notification, Notifications.Notification, Notifications}

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

  def perform(%Oban.Job{args: %{"organization_id" => org_id, "sync_hsm" => true}}) do
    Logger.info("Starting background sync of HSM templates for org #{org_id}")

    case Templates.sync_hsms_from_bsp(org_id) do
      :ok ->
        Logger.info("HSM template sync completed successfully for org_id: #{org_id}")

        send_notification(
          org_id,
          "HSM template sync completed successfully.",
          Notifications.types().info
        )

      {:error, reason} ->
        Logger.error(
          "Failed to sync HSM templates for org_id: #{org_id}, reason: #{inspect(reason)}"
        )

        send_notification(
          org_id,
          "Failed to sync HSM templates: #{inspect(reason)}",
          Notifications.types().critical
        )
    end

    :ok
  end

  @spec send_notification(non_neg_integer(), String.t(), String.t()) ::
          {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  defp send_notification(org_id, message, severity) do
    Notifications.create_notification(%{
      category: "HSM template",
      message: message,
      severity: severity,
      organization_id: org_id,
      entity: %{Provider: "Gupshup"}
    })
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
