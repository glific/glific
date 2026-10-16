defmodule Glific.LlmCalls.LlmCall do
  @moduledoc """
  A Kaapi LLM call made from a flow node, recorded when Kaapi posts its callback.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Contacts.Contact,
    Flows.Flow,
    Partners.Organization
  }

  @required_fields [:organization_id, :flow_id, :contact_id]
  @optional_fields [
    :success,
    :error,
    :provider_response_id,
    :conversation_id,
    :provider,
    :model,
    :input_from_user,
    :input_to_llm,
    :output_from_llm,
    :output_to_user,
    :input_guardrail,
    :output_guardrail,
    :tokens
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          success: boolean() | nil,
          error: String.t() | nil,
          provider_response_id: String.t() | nil,
          conversation_id: String.t() | nil,
          provider: String.t() | nil,
          model: String.t() | nil,
          input_from_user: String.t() | nil,
          input_to_llm: String.t() | nil,
          output_from_llm: String.t() | nil,
          output_to_user: String.t() | nil,
          input_guardrail: [map()] | nil,
          output_guardrail: [map()] | nil,
          tokens: map() | nil,
          flow_id: non_neg_integer | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "llm_calls" do
    field :success, :boolean
    field :error, :string
    field :provider_response_id, :string
    field :conversation_id, :string
    field :provider, :string
    field :model, :string
    field :input_from_user, :string
    field :input_to_llm, :string
    field :output_from_llm, :string
    field :output_to_user, :string
    field :input_guardrail, {:array, :map}
    field :output_guardrail, {:array, :map}
    field :tokens, :map

    belongs_to :flow, Flow
    belongs_to :contact, Contact
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc "Standard changeset pattern we use for all data types"
  @spec changeset(LlmCall.t(), map()) :: Ecto.Changeset.t()
  def changeset(llm_call, attrs) do
    llm_call
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:organization_id)
  end
end
