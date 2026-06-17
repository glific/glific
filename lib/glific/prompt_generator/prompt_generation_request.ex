defmodule Glific.PromptGenerator.PromptGenerationRequest do
  @moduledoc """
  Ecto schema for a prompt-generation request.

  A request is created when an NGO submits their 9-question answers for LLM-based
  WhatsApp chatbot system-prompt generation via Kaapi. The row starts as `:in_progress`,
  and transitions to `:ready` (with `generated_prompt` populated) or `:failed` (with
  `error_message`) when Kaapi posts its async callback.

  ## Callback correlation

  We generate a UUID `request_id` before calling Kaapi and embed it as
  `request_metadata.request_id` in the payload. Kaapi echoes it back as
  `metadata.request_id` in the async callback body — this is the lookup key.
  `kaapi_job_id` is stored for informational purposes only (from the Kaapi sync ack)
  and is NOT the callback correlation key.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{
    Partners.Organization,
    Users.User
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          inputs: map() | nil,
          generated_prompt: String.t() | nil,
          status: atom() | nil,
          request_id: String.t() | nil,
          kaapi_job_id: String.t() | nil,
          error_message: String.t() | nil,
          organization_id: non_neg_integer() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          user_id: non_neg_integer() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields [
    :inputs,
    :status,
    :request_id,
    :organization_id
  ]

  @optional_fields [
    :generated_prompt,
    :kaapi_job_id,
    :error_message,
    :user_id
  ]

  schema "prompt_generation_requests" do
    field(:inputs, :map)
    field(:generated_prompt, :string)
    field(:status, Ecto.Enum, values: [:in_progress, :ready, :failed], default: :in_progress)
    field(:request_id, :string)
    field(:kaapi_job_id, :string)
    field(:error_message, :string)

    belongs_to(:organization, Organization)
    belongs_to(:user, User)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Standard changeset for `PromptGenerationRequest`.

  ## Examples

      iex> PromptGenerationRequest.changeset(%PromptGenerationRequest{}, %{inputs: %{}, status: :in_progress, request_id: "uuid-123", organization_id: 1})
      %Ecto.Changeset{valid?: true}
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(prompt_generation_request, attrs) do
    prompt_generation_request
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:request_id, :organization_id],
      name: :prompt_generation_requests_request_id_organization_id_index
    )
  end
end
