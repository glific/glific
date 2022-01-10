defmodule GlificWeb.Resolvers.Flows do
  @moduledoc """
  Flow Resolver which sits between the GraphQL schema and Glific Flow Context API.
  This layer basically stiches together one or more calls to resolve the incoming queries.
  """
  import GlificWeb.Gettext

  alias Glific.{
    Contacts.Contact,
    Flows,
    Flows.Broadcast,
    Flows.Flow,
    Flows.FlowContext,
    Groups.Group,
    Repo,
    State,
    Users.User
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
    do_op_flow(id, params, user, &Flows.update_flow/2)
  end

  @doc false
  @spec export_flow(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, %{export_data: map}}
  def export_flow(_, %{id: flow_id}, _) do
    {:ok, %{export_data: Flows.export_flow(flow_id)}}
  end

  @doc false
  @spec import_flow(Absinthe.Resolution.t(), %{flow: map()}, %{context: map()}) ::
          {:ok, %{success: boolean()}}
  def import_flow(_, %{flow: flow}, %{context: %{current_user: user}}) do
    {:ok, %{success: Flows.import_flow(flow, user.organization_id)}}
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
  def flow_get(_, %{id: id}, %{context: %{current_user: user}}) do
    with %Flow{} = flow <- State.get_flow(user, id) do
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
  def publish_flow(_, %{uuid: uuid}, _) do
    with {:ok, flow} <- Repo.fetch_by(Flow, %{uuid: uuid}),
         {:ok, _flow} <- Flows.publish_flow(flow) do
      {:ok, %{success: true, errors: nil}}
    else
      {:errors, errors} ->
        {:ok, %{success: true, errors: errors}}

      {:error, errors} ->
        {:ok, %{success: true, errors: %{key: hd(errors), message: hd(tl(errors))}}}

      _ ->
        {:error, dgettext("errors", "Something went wrong.")}
    end
  end

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
  def start_contact_flow(_, %{flow_id: flow_id, contact_id: contact_id}, %{
        context: %{current_user: user}
      }) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: contact_id, organization_id: user.organization_id}),
         {:ok, flow_id} <- Glific.parse_maybe_integer(flow_id),
         {:ok, _flow} <- Flows.start_contact_flow(flow_id, contact) do
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
  Start a flow for all contacts of a group
  """
  @spec start_group_flow(Absinthe.Resolution.t(), %{flow_id: integer, group_id: integer}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def start_group_flow(_, %{flow_id: flow_id, group_id: group_id}, %{
        context: %{current_user: user}
      }) do
    with {:ok, flow} <-
           Repo.fetch_by(Flow, %{id: flow_id, organization_id: user.organization_id}),
         {:ok, group} <-
           Repo.fetch_by(Group, %{id: group_id, organization_id: user.organization_id}),
         {:ok, _flow} <- Flows.start_group_flow(flow, group) do
      {:ok, %{success: true}}
    end
  end

  @doc """
  Make a copy a flow
  """
  @spec copy_flow(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def copy_flow(_, %{id: id, input: params}, %{
        context: %{current_user: user}
      }) do
    do_op_flow(id, params, user, &Flows.copy_flow/2)
  end

  @spec do_op_flow(
          non_neg_integer,
          map(),
          User.t(),
          (Flow.t(), map() -> {:ok, Flow.t()} | {:error, String.t()})
        ) ::
          {:ok, any} | {:error, any}
  defp do_op_flow(id, params, user, fun) do
    with {:ok, flow} <- Repo.fetch_by(Flow, %{id: id, organization_id: user.organization_id}),
         {:ok, flow} <- fun.(flow, params) do
      {:ok, %{flow: flow}}
    end
  end

  @doc """
  Get broadcast stats for a flow
  """
  @spec broadcast_stats(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def broadcast_stats(_, %{flow_boradcast_id: flow_boradcast_id}, _),
    do: Broadcast.broadcast_stats(flow_boradcast_id)
end
