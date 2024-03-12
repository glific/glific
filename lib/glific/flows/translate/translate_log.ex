defmodule Glific.Flows.Translate.TranslateLog do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false
  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Repo
  }

  @required_fields [
    :text,
    :translation_engine,
    :source_language,
    :destination_language,
    :error,
    :organization_id
  ]
  @optional_fields [:translated_text, :status]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          text: String.t() | nil,
          translated_text: String.t() | nil,
          translation_engine: String.t() | nil,
          source_language: String.t() | nil,
          destination_language: String.t() | nil,
          status: boolean,
          error: String.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "translate_logs" do
    field(:text, :string)
    field(:translated_text, :string)
    field(:translation_engine, :string)
    field(:source_language, :string)
    field(:destination_language, :string)
    field(:status, :boolean, default: false)
    field(:error, :string)

    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(TranslateLog.t(), map()) :: Ecto.Changeset.t()
  def changeset(translate_log, attrs) do
    translate_log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:organization_id)
  end

  @doc false
  @spec update_translate_log(TranslateLog.t(), map()) ::
          {:ok, TranslateLog.t()} | {:error, Ecto.Changeset.t()}
  def update_translate_log(translate_log, attrs) do
    translate_log
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc false
  @spec create_translate_log(map()) :: {:ok, TranslateLog.t()} | {:error, Ecto.Changeset.t()}
  def create_translate_log(attrs \\ %{}) do
    %TranslateLog{}
    |> TranslateLog.changeset(attrs)
    |> Repo.insert()
  end
end
