defmodule Glific.Flows.Templating do
  @moduledoc """
  The Case object which encapsulates one category in a given node.
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.{
    Flows,
    Flows.FlowContext,
    Messages.Message,
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
  @spec process(map(), map()) :: {Templating.t(), map()}
  def process(json, uuid_map) when is_nil(json), do: {json, uuid_map}

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
    {:ok, template} = Glific.Repo.fetch_by(SessionTemplate, %{uuid: uuid})

    templating = %Templating{
      uuid: json["uuid"],
      name: json["template"]["name"],
      template: template,
      variables: json["variables"],
      expression: nil,
      localization: json["localization"]
    }

    {templating, Map.put(uuid_map, templating.uuid, {:templating, templating})}
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
    opts =
      Jason.decode!(json_string)
      |> Glific.atomize_keys()
      |> update_session_template()

    struct!(Templating, opts)
  end

  defp update_session_template(attrs) do
    {:ok, template} = Glific.Repo.fetch_by(SessionTemplate, %{uuid: attrs[:uuid]})
    Map.put(attrs, :template, template)
  end
end
