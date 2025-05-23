defmodule GlificWeb.Resolvers.Templates do
  @moduledoc """
  Templates Resolver which sits between the GraphQL schema and Glific Templates Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  require Logger

  alias Glific.{
    Notifications,
    Repo,
    Templates,
    Templates.SessionTemplate,
    Templates.TemplateWorker
  }

  @doc """
  Get a specific session template by id
  """
  @spec session_template(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def session_template(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, session_template} <-
           Repo.fetch_by(SessionTemplate, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{session_template: session_template}}
  end

  @doc """
  Get the list of session templates filtered by args
  """
  @spec session_templates(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def session_templates(_, args, _) do
    {:ok, Templates.list_session_templates(args)}
  end

  @doc """
  Get the count of session templates filtered by args
  """
  @spec count_session_templates(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, integer}
  def count_session_templates(_, args, _) do
    {:ok, Templates.count_session_templates(args)}
  end

  @doc false
  @spec create_session_template(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_session_template(_, %{input: params}, _) do
    with {:ok, session_template} <- Templates.create_session_template(params) do
      {:ok, %{session_template: session_template}}
    end
  end

  @doc false
  @spec update_session_template(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_session_template(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, session_template} <-
           Repo.fetch_by(SessionTemplate, %{id: id, organization_id: user.organization_id}),
         {:ok, session_template} <- Templates.update_session_template(session_template, params) do
      {:ok, %{session_template: session_template}}
    end
  end

  @doc false
  @spec edit_approved_template(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def edit_approved_template(_, %{id: id, input: params}, _) do
    with {:ok, session_template} <- Templates.edit_approved_template(id, params) do
      {:ok, %{session_template: session_template}}
    end
  end

  @doc false
  @spec delete_session_template(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_session_template(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, session_template} <-
           Repo.fetch_by(SessionTemplate, %{id: id, organization_id: user.organization_id}) do
      Templates.delete_session_template(session_template)
    end
  end

  @doc """
  Converting a message to message template
  """
  @spec create_template_from_message(
          Absinthe.Resolution.t(),
          %{message_id: integer, input: map()},
          %{context: map()}
        ) ::
          {:ok, any} | {:error, any}
  def create_template_from_message(_, params, _) do
    with {:ok, session_template} <- Templates.create_template_from_message(params) do
      {:ok, %{session_template: session_template}}
    end
  end

  @doc """
  Import pre approved templates
  """
  @spec import_templates(Absinthe.Resolution.t(), %{data: String.t()}, %{
          context: map()
        }) :: {:ok, any} | {:error, any}
  def import_templates(_, %{data: data}, %{context: %{current_user: user}}),
    do: Templates.import_templates(user.organization_id, data)

  @doc """
  Bulk applying templates from CSV
  """
  @spec bulk_apply_templates(Absinthe.Resolution.t(), %{data: String.t()}, %{
          context: map()
        }) :: {:ok, any} | {:error, any}
  def bulk_apply_templates(_, %{data: data}, %{context: %{current_user: user}}),
    do: Templates.bulk_apply_templates(user.organization_id, data)

  @doc """
  Sync hsm with bsp
  """
  @spec sync_hsm_template(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, String.t()}
  def sync_hsm_template(_, _, %{context: %{current_user: %{organization_id: nil}}}) do
    {:error, "organization_id is not given"}
  end

  def sync_hsm_template(_, _, %{context: %{current_user: user}}) do
    queue_hsm_sync(user.organization_id)
  end

  @spec queue_hsm_sync(non_neg_integer()) :: {:ok, map()} | {:error, String.t()}
  defp queue_hsm_sync(organization_id) do
    args = %{"organization_id" => organization_id, "sync_hsm" => true}

    case Oban.insert(TemplateWorker.new(args)) do
      {:ok, _job} ->
        Notifications.create_notification(%{
          category: "HSM template",
          message: "Syncing of HSM templates has started in the background.",
          severity: Notifications.types().info,
          organization_id: organization_id,
          entity: %{Provider: "Gupshup"}
        })

        {:ok, %{message: "HSM sync job queued successfully"}}

      {:error, reason} ->
        error_message =
          "Failed to queue HSM sync job for organization #{organization_id}: #{inspect(reason)}"

        Logger.error(error_message)
        {:error, error_message}
    end
  end

  @doc """
  Report mail to gupshup
  Returns mail log id
  """
  @spec report_to_gupshup(
          Absinthe.Resolution.t(),
          map(),
          %{context: map()}
        ) :: {:ok, any} | {:error, any}
  def report_to_gupshup(_, attr, %{context: %{current_user: user}}) do
    Templates.report_to_gupshup(
      user.organization_id,
      Map.get(attr, :template_id),
      Map.get(attr, :cc, %{})
    )
  end
end
