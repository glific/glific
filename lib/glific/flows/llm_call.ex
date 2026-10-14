defmodule Glific.Flows.LlmCall do
  @moduledoc """
  A Kaapi LLM call made from a flow node, recorded when Kaapi posts its callback.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__

  alias Glific.{
    Contacts.Contact,
    Flows.Flow,
    Flows.WebhookLog,
    Partners.Organization,
    Repo
  }

  @required_fields [:organization_id]
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
    :tokens,
    :flow_id,
    :contact_id
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

  @doc "Create an LLM call record"
  @spec create_llm_call(map()) :: {:ok, LlmCall.t()} | {:error, Ecto.Changeset.t()}
  def create_llm_call(attrs) do
    %LlmCall{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc "Record an LLM call from the raw Kaapi callback `result` and its parsed `response`."
  @spec record_callback(non_neg_integer(), map(), map()) ::
          {:ok, LlmCall.t()} | {:error, Ecto.Changeset.t()}
  def record_callback(organization_id, result, response) do
    metadata = result["metadata"] || %{}
    llm_response = get_in(result, ["data", "response"]) || %{}
    input_guardrail = metadata["input_guardrail"]
    output_guardrail = metadata["output_guardrail"]
    output = text_output(llm_response["output"])
    question = input_guardrail["input_from_user"] || question(response["webhook_log_id"])

    create_llm_call(%{
      organization_id: organization_id,
      flow_id: response["flow_id"],
      contact_id: response["contact_id"],
      success: result["success"],
      error: result["error"],
      provider_response_id: llm_response["provider_response_id"],
      conversation_id: llm_response["conversation_id"],
      provider: llm_response["provider"],
      model: llm_response["model"],
      input_from_user: question,
      input_to_llm: input_guardrail["input_to_llm"] || question,
      output_from_llm: output_guardrail["output_from_llm"] || output,
      output_to_user: output_guardrail["output_to_user"] || output,
      input_guardrail: input_guardrail["validators"],
      output_guardrail: output_guardrail["validators"],
      tokens: get_in(result, ["data", "usage"])
    })
  end

  # Without an input guardrail the callback doesn't echo the input, so read the question the
  # flow node sent from its webhook log.
  @spec question(non_neg_integer() | nil) :: String.t() | nil
  defp question(nil), do: nil

  defp question(webhook_log_id) do
    case Repo.get(WebhookLog, webhook_log_id) do
      %WebhookLog{request_json: %{"question" => question}} -> question
      _ -> nil
    end
  end

  @spec text_output(map() | nil) :: String.t() | nil
  defp text_output(%{"type" => "text", "content" => %{"value" => value}}), do: value
  defp text_output(_output), do: nil
end
