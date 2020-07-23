defmodule Glific.Flows.Templating do
  @moduledoc """
  The Case object which encapsulates one category in a given node.
  """
  alias __MODULE__

  use Ecto.Schema

  alias Glific.{
    Flows,
    Templates.SessionTemplate
  }

  @required_fields [:template]

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          template: SessionTemplate.t() | nil,
          variables: list()
        }

  embedded_schema do
    field :uuid, Ecto.UUID
    field :name, :string
    field :variables, {:array, :string}, default: []
    embeds_one :template, SessionTemplate
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), map()) :: {Templating.t(), map()}
  def process(json, uuid_map) when is_nil(json), do: {json, uuid_map}

  def process(json, uuid_map) do
    Flows.check_required_fields(json, @required_fields)

    {:ok, template} =
      Glific.Repo.fetch_by(SessionTemplate, %{uuid: String.downcase(json["template"]["uuid"])})

    templating = %Templating{
      uuid: json["template"]["uuid"],
      name: json["template"]["name"],
      template: template,
      variables: json["variables"]
    }

    {templating, Map.put(uuid_map, templating.uuid, {:templating, templating})}
  end
end
