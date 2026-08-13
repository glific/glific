defmodule GlificWeb.Schema.SimulatorTypes do
  @moduledoc """
  GraphQL surface for the staff-console flow preview simulator's web-channel tab
  (`plans/web-channel/blocks-contract.md` §13). `simulatorWebMessage` is the frozen interface
  in §13.2 — do not change field names or shapes here without updating the contract first.
  """

  use Absinthe.Schema.Notation

  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :simulator_web_message_result do
    field :message, :message
    field :errors, list_of(:input_error)
  end

  @desc "Input for simulatorWebMessage — see blocks-contract.md §13.2"
  input_object :simulator_web_message_input do
    @desc "Must be a simulator contact of the caller's organization"
    field :contact_id, non_null(:id)
    field :type, non_null(:message_type_enum)

    @desc "Text body, or media caption"
    field :body, :string

    @desc "Media only — an already-hosted URL (staff uploadMedia returns one)"
    field :url, :string
    field :content_type, :string

    @desc "Location only"
    field :latitude, :float
    field :longitude, :float

    @desc "Blocks response only — the outbound :blocks message being answered"
    field :message_id, :id
    field :component, :string
    field :values, :json
    field :summary, :string
    field :context, :json
  end

  object :simulator_mutations do
    field :simulator_web_message, :simulator_web_message_result do
      arg(:input, non_null(:simulator_web_message_input))
      middleware(Authorize, :staff)
      resolve(&Resolvers.Simulator.simulator_web_message/3)
    end
  end
end
