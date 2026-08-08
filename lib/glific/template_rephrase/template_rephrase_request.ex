defmodule Glific.TemplateRephrase.TemplateRephraseRequest do
  @moduledoc """
  Ecto schema for a template-rephrase request.

  A request is created when a user asks to rephrase a WhatsApp template body via one of
  three actions (professional, utility, custom) using Kaapi's async LLM service. The row
  starts as `:in_progress`, and transitions to `:ready` (with `rephrased_text` populated)
  or `:failed` (with `error_message`) when Kaapi posts its async callback.

  ## Callback correlation

  We generate a UUID `request_id` before calling Kaapi and embed it as
  `request_metadata.request_id` in the payload. Kaapi echoes it back as
  `metadata.request_id` in the async callback body — this is the lookup key.
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
          original_text: String.t() | nil,
          action: atom() | nil,
          custom_prompt: String.t() | nil,
          rephrased_text: String.t() | nil,
          status: atom() | nil,
          request_id: String.t() | nil,
          error_message: String.t() | nil,
          organization_id: non_neg_integer() | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          user_id: non_neg_integer() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @required_fields [
    :original_text,
    :action,
    :status,
    :request_id,
    :organization_id
  ]

  @optional_fields [
    :custom_prompt,
    :rephrased_text,
    :error_message,
    :user_id
  ]

  schema "template_rephrase_requests" do
    field(:original_text, :string)
    field(:action, Ecto.Enum, values: [:professional, :utility, :custom])
    field(:custom_prompt, :string)
    field(:rephrased_text, :string)
    field(:status, Ecto.Enum, values: [:in_progress, :ready, :failed], default: :in_progress)
    field(:request_id, :string)
    field(:error_message, :string)

    belongs_to(:organization, Organization)
    belongs_to(:user, User)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Standard changeset for `TemplateRephraseRequest`.

  ## Examples

      iex> TemplateRephraseRequest.changeset(%TemplateRephraseRequest{}, %{original_text: "Hi {{1}}", action: :professional, status: :in_progress, request_id: "uuid-123", organization_id: 1})
      %Ecto.Changeset{valid?: true}
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(template_rephrase_request, attrs) do
    template_rephrase_request
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:request_id, :organization_id],
      name: :template_rephrase_requests_request_id_organization_id_index
    )
  end
end
