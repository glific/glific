defmodule GlificWeb.Resolvers.Flows do
  @moduledoc """
  Flow Resolver which sits between the GraphQL schema and Glific Flow Context API.
  This layer basically stitches together one or more calls to resolve the incoming queries.
  """
  use Gettext, backend: GlificWeb.Gettext

  alias Glific.{
    Contacts.Contact,
    Flows,
    Flows.Broadcast,
    Flows.Flow,
    Flows.FlowContext,
    Flows.FlowCount,
    Flows.Translate.Export,
    Flows.Translate.Import,
    Repo,
    State,
    TextToFlow
  }

  @doc """
  Get a specific flow by id
  """
  @spec flow(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def flow(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, flow} <- Repo.fetch_by(Flow, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{flow: flow}}
  end

  @doc """
  Get the list of flows
  """
  @spec flows(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [Flow]}
  def flows(_, args, _) do
    {:ok, Flows.list_flows(args)}
  end

  @doc """
  Get the count of flows filtered by args
  """
  @spec count_flows(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_flows(_, args, _) do
    {:ok, Flows.count_flows(args)}
  end

  @doc false
  @spec create_flow(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_flow(_, %{input: params}, _) do
    with {:ok, flow} <- Flows.create_flow(params) do
      {:ok, %{flow: flow}}
    end
  end

  @doc false
  @spec update_flow(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_flow(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, flow} <- Repo.fetch_by(Flow, %{id: id, organization_id: user.organization_id}),
         {:ok, flow} <- Flows.update_flow(flow, params) do
      {:ok, %{flow: flow}}
    end
  end

  @doc false
  @spec export_flow(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, %{export_data: map}}
  def export_flow(_, %{id: flow_id}, _) do
    with exported_flow when is_map(exported_flow) <- Flows.export_flow(flow_id) do
      {:ok, %{export_data: exported_flow}}
    end
  end

  @doc false
  @spec export_flow_localization(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, %{export_data: String.t()}}
  def export_flow_localization(_, %{id: flow_id} = args, %{
        context: %{current_user: user}
      }) do
    add_translation = Map.get(args, :add_translation, true)

    if add_translation,
      do: Glific.Metrics.increment("Export with auto translate"),
      else: Glific.Metrics.increment("Export without auto translate")

    # load the flow
    data =
      user.organization_id
      |> Flows.get_complete_flow(flow_id)
      |> Export.export_localization(add_translation)
      |> CSV.encode(delimiter: "\n")
      |> Enum.join("")

    {:ok, %{export_data: data}}
  end

  @doc false
  @spec import_flow(Absinthe.Resolution.t(), %{flow: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def import_flow(_, %{flow: flow}, %{context: %{current_user: user}}) do
    {:ok, %{status: Flows.import_flow(flow, user.organization_id)}}
  end

  @doc false
  @spec import_flow_localization(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def import_flow_localization(_, %{localization: data, id: flow_id}, %{
        context: %{current_user: user}
      }) do
    Glific.Metrics.increment("Import translations")
    flow = Flows.get_complete_flow(user.organization_id, flow_id)

    {:ok, stream} = StringIO.open(data)

    stream
    |> IO.binstream(:line)
    |> CSV.decode!(escape_max_lines: 50)
    |> Enum.into([])
    |> Import.import_localization(flow)

    {:ok, %{success: true}}
  end

  @doc false
  @spec inline_flow_localization(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def inline_flow_localization(_, %{id: flow_id}, %{
        context: %{current_user: user}
      }) do
    user.organization_id
    |> Flows.get_complete_flow(flow_id)
    |> Export.translate()

    {:ok, %{success: true}}
  end

  @doc false
  @spec delete_flow(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_flow(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, flow} <- Repo.fetch_by(Flow, %{id: id, organization_id: user.organization_id}) do
      Flows.delete_flow(flow)
    end
  end

  @doc """
  Grab a flow or nil if possible for this user
  """
  @spec flow_get(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def flow_get(_, params, %{context: %{current_user: user}}) do
    flow_id = Glific.parse_maybe_integer!(params.id)

    with %Flow{} = flow <- State.get_flow(user, flow_id, Map.get(params, :is_forced, false)) do
      {:ok, %{flow: flow}}
    end
  end

  @doc """
  Release a flow or nil if possible for this user
  """
  @spec flow_release(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def flow_release(_, _params, %{context: %{current_user: user}}) do
    {:ok, State.release_flow(user)}
  end

  @doc """
  Publish a flow
  """
  @spec publish_flow(Absinthe.Resolution.t(), %{uuid: String.t()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def publish_flow(_, %{uuid: uuid}, %{context: %{current_user: user}}) do
    with {:ok, flow} <- Repo.fetch_by(Flow, %{uuid: uuid}),
         {:ok, _flow} <- Flows.publish_flow(flow, user.id) do
      {:ok, %{success: true, errors: nil}}
    else
      {:errors, errors} ->
        {:ok, %{success: false, errors: errors}}

      {:error, errors} ->
        {:ok, %{success: false, errors: make_error(errors)}}
    end
  end

  @spec make_error(any) :: map()
  defp make_error(error) when is_list(error),
    do: %{key: hd(error), message: hd(tl(error))}

  defp make_error(error),
    do: %{key: "Database Error", message: inspect(error)}

  @doc """
  Start a flow for a contact
  """
  @spec start_contact_flow(
          Absinthe.Resolution.t(),
          %{flow_id: integer | String.t(), contact_id: integer},
          %{
            context: map()
          }
        ) ::
          {:ok, any} | {:error, any}
  def start_contact_flow(_, %{flow_id: flow_id, contact_id: contact_id} = params, %{
        context: %{current_user: user}
      }) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: contact_id, organization_id: user.organization_id}),
         {:ok, flow_id} <- Glific.parse_maybe_integer(flow_id),
         {:ok, _flow} <- Flows.start_contact_flow(flow_id, contact, params[:default_results]) do
      {:ok, %{success: true}}
    end
  end

  @doc """
  Start a flow for a WhatsApp group
  """
  @spec start_wa_group_flow(
          Absinthe.Resolution.t(),
          %{flow_id: integer, wa_group_id: integer},
          %{context: map()}
        ) :: {:ok, any} | {:error, any}
  def start_wa_group_flow(_, %{flow_id: flow_id, wa_group_id: wa_group_id}, %{
        context: %{current_user: user}
      }) do
    with {:ok, wa_group_id} <- Glific.parse_maybe_integer(wa_group_id),
         {:ok, flow_id} <- Glific.parse_maybe_integer(flow_id),
         {:ok, _flow} <- Flows.start_wa_group_flow(flow_id, wa_group_id, user.organization_id) do
      {:ok, %{success: true}}
    end
  end

  @doc """
  Start a flow for all groups of a wa group collection
  """
  @spec start_wa_group_collection_flow(
          Absinthe.Resolution.t(),
          %{flow_id: integer, group_id: String.t()},
          %{
            context: map()
          }
        ) ::
          {:ok, any} | {:error, any}
  def start_wa_group_collection_flow(_, %{flow_id: flow_id, group_id: group_id} = _params, %{
        context: %{current_user: _user}
      }) do
    group_id = [String.to_integer(group_id)]

    with {:ok, flow} <- Flows.fetch_flow(flow_id),
         {:ok, _flow} <- Flows.start_wa_group_flow(flow, group_id) do
      {:ok, %{success: true}}
    end
  end

  @doc """
  Resume a flow for a contact
  """
  @spec resume_contact_flow(
          Absinthe.Resolution.t(),
          %{flow_id: integer | String.t(), contact_id: integer, result: map()},
          %{
            context: map()
          }
        ) ::
          {:ok, any} | {:error, any}
  def resume_contact_flow(_, %{flow_id: flow_id, contact_id: contact_id, result: result}, %{
        context: %{current_user: user}
      }) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: contact_id, organization_id: user.organization_id}),
         {:ok, flow_id} <- Glific.parse_maybe_integer(flow_id) do
      case FlowContext.resume_contact_flow(contact, flow_id, result) do
        {:ok, _flow_context, _messages} ->
          {:ok, %{success: true}}

        {:error, message} ->
          {:ok, %{success: true, errors: %{key: "Flow", message: message}}}
      end
    end
  end

  @doc """
  Terminate all flows for a contact
  """
  @spec terminate_contact_flows(
          Absinthe.Resolution.t(),
          %{contact_id: integer},
          map()
        ) ::
          {:ok, any} | {:error, any}
  def terminate_contact_flows(_, %{contact_id: contact_id}, _context) do
    with {:ok, contact_id} <- Glific.parse_maybe_integer(contact_id),
         :ok <- Flows.terminate_contact_flows?(contact_id) do
      {:ok, %{success: true}}
    end
  end

  @doc """
  Start a flow for all contacts of a group
  """
  @spec start_group_flow(Absinthe.Resolution.t(), %{flow_id: integer, group_id: String.t()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def start_group_flow(_, %{flow_id: flow_id, group_id: group_id} = params, %{
        context: %{current_user: _user}
      }) do
    group_id = [String.to_integer(group_id)]

    with {:ok, flow} <- Flows.fetch_flow(flow_id),
         {:ok, _flow} <- Flows.start_group_flow(flow, group_id, params[:default_results]) do
      {:ok, %{success: true}}
    end
  end

  @doc """
  Make a copy a flow
  """
  @spec copy_flow(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def copy_flow(_, %{id: id, input: params}, _) do
    org_id = Map.get(params, :organization_id)
    {:ok, template} = Repo.fetch_by(Flow, %{id: id})

    if template.is_template do
      Glific.Metrics.increment("Template flows on UI", org_id)
    end

    do_copy_flow(id, params, &Flows.copy_flow/2)
  end

  @spec do_copy_flow(
          non_neg_integer,
          map(),
          (Flow.t(), map() -> {:ok, Flow.t()} | {:error, String.t()})
        ) ::
          {:ok, any} | {:error, any}
  defp do_copy_flow(id, params, fun) do
    with {:ok, flow} <- Flows.fetch_flow(id),
         {:ok, flow} <- fun.(flow, params) do
      {:ok, %{flow: flow}}
    end
  end

  @doc """
  Get broadcast stats for a flow
  """
  @spec broadcast_stats(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def broadcast_stats(_, %{message_broadcast_id: message_broadcast_id}, _),
    do: Broadcast.broadcast_stats(message_broadcast_id)

  @doc """
  Reset the flow counts for a specific flow
  """
  @spec reset_flow_count(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def reset_flow_count(_, %{flow_id: flow_id}, _) do
    FlowCount.reset_flow_count(flow_id)
    {:ok, %{success: true}}
  end

  @doc """
  Generate a flow from a text prompt using AI
  """
  @spec generate_flow_from_text(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def generate_flow_from_text(_, %{uuid: uuid, prompt: prompt}, %{
        context: %{current_user: user}
      }) do
    with {:ok, flow} <- Repo.fetch_by(Flow, %{uuid: uuid, organization_id: user.organization_id}),
         {:ok, flow_json} <- TextToFlow.generate_flow(flow.name, prompt, user.organization_id, uuid) do
      _revision = Flows.create_flow_revision(flow_json, user.id)
      {:ok, %{flow_data: flow_json, success: true}}
    else
      {:error, reason} when is_binary(reason) ->
        {:ok, %{errors: [%{message: reason}], success: false}}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          changeset.errors
          |> Enum.map(fn {field, {message, _}} ->
            %{key: to_string(field), message: message}
          end)

        {:ok, %{errors: errors, success: false}}

      {:error, reason} ->
        {:ok, %{errors: [%{message: inspect(reason)}], success: false}}
    end
  end
end
