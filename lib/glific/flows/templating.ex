defmodule Glific.Flows.Templating do
  @moduledoc """
  The Case object which encapsulates one category in a given node.
  """
  alias __MODULE__

  use Ecto.Schema

  require Logger

  alias Glific.{
    Flows,
    Flows.FlowContext,
    Messages.Message,
    Notifications,
    Repo,
    Templates.SessionTemplate
  }

  @required_fields [:template]

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          template: SessionTemplate.t() | nil,
          variables: list(),
          expression: String.t() | nil,
          localization: map()
        }

  embedded_schema do
    field :uuid, Ecto.UUID
    field :name, :string
    field :expression, :string
    field :localization, :map
    field :variables, {:array, :string}, default: []
    embeds_one :template, SessionTemplate
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map() | nil, map()) :: {Templating.t(), map()}
  def process(nil, uuid_map), do: {nil, uuid_map}

  def process(%{"expression" => expression} = json, uuid_map)
      when is_binary(expression) == true do
    templating = %Templating{
      expression: expression,
      uuid: json["uuid"]
    }

    {templating, Map.put(uuid_map, templating.uuid, {:templating, templating})}
  end

  def process(json, uuid_map) do
    Flows.check_required_fields(json, @required_fields)
    uuid = json["template"]["uuid"]

    do_process_template(uuid, json, uuid_map)
  end

  @spec do_process_template(nil | String.t(), map(), map()) ::
          {nil, map()} | {Templating.t(), map()}
  defp do_process_template(nil, json, uuid_map) do
    Logger.error("UUID is nil, skipping templating. #{inspect(json)}")
    create_flow_template_notification("Template expression is null in the flow", json, uuid_map)
  end

  defp do_process_template(uuid, json, uuid_map) do
    case Glific.Repo.fetch_by(SessionTemplate, %{uuid: uuid}) do
      {:ok, template} ->
        variables = if is_list(json["variables"]), do: json["variables"], else: []

        templating = %Templating{
          uuid: json["uuid"],
          name: json["template"]["name"],
          template: template,
          variables: Enum.take(variables, template.number_parameters),
          expression: nil,
          localization: json["localization"]
        }

        {templating, Map.put(uuid_map, templating.uuid, {:templating, templating})}

      error ->
        Logger.error(
          "Template not found, skipping templating. #{inspect(json)} and error #{inspect(error)}"
        )

        create_flow_template_notification(
          "Template not found, skipping templating",
          json,
          uuid_map
        )
    end
  end

  @spec create_flow_template_notification(String.t(), map(), map()) :: {nil, map()}
  defp create_flow_template_notification(message, json, uuid_map) do
    %{
      category: "Template",
      message: message,
      severity: Notifications.types().warning,
      organization_id: Repo.get_organization_id(),
      entity: %{template_type: json["template"]}
    }
    |> Notifications.create_notification()

    {nil, uuid_map}
  end

  @doc """
    We need to perform the execute in case template is an expression
  """
  @spec execute(Templating.t(), FlowContext.t(), [Message.t()]) :: Templating.t() | nil
  def execute(%{expression: expression} = _templating, context, _messages)
      when is_binary(expression) == true do
    FlowContext.parse_context_string(context, expression)
    |> Glific.execute_eex()
    |> ensure_template_struct()
  end

  def execute(templating, _context, _messages), do: templating

  defp ensure_template_struct(json_string) do
    Jason.decode(json_string)
    |> case do
      {:ok, json} ->
        opts =
          json
          |> Glific.atomize_keys()
          |> update_session_template()

        struct!(Templating, opts)

      {:error, error} ->
        Logger.error(
          "Error parsing json string  #{inspect(json_string)} with error: #{inspect(error)}"
        )

        nil
    end
  end

  @spec update_session_template(map()) :: map()
  defp update_session_template(%{uuid: uuid} = attrs) when uuid not in ["", nil] do
    {:ok, template} = Glific.Repo.fetch_by(SessionTemplate, %{uuid: attrs[:uuid]})
    Map.put(attrs, :template, template)
  end

  defp update_session_template(attrs), do: attrs
end
