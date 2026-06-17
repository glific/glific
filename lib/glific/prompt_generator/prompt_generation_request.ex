defmodule Glific.PromptGenerator.PromptGenerationRequest do
  @moduledoc """
  Ecto schema for a prompt-generation request.

  A request is created when an NGO submits their 9-question answers for LLM-based
  WhatsApp chatbot system-prompt generation via Kaapi. The row starts as `:in_progress`,
  and transitions to `:ready` (with `generated_prompt` populated) or `:failed` (with
  `error_message`) when Kaapi posts its async callback.
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
    field(:kaapi_job_id, :string)
    field(:error_message, :string)

    belongs_to(:organization, Organization)
    belongs_to(:user, User)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset for `PromptGenerationRequest`.

  ## Examples

      iex> PromptGenerationRequest.changeset(%PromptGenerationRequest{}, %{inputs: %{}, status: :in_progress, organization_id: 1})
      %Ecto.Changeset{valid?: true}
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(prompt_generation_request, attrs) do
    prompt_generation_request
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:kaapi_job_id, :organization_id],
      name: :prompt_generation_requests_kaapi_job_id_organization_id_index
    )
  end
end
