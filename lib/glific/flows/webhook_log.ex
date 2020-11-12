defmodule Glific.Flows.WebhookLog do
  @moduledoc """
  The webhook log object
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    Contacts.Contact,
    Flows.Flow,
    Partners.Organization,
    Repo
  }

  @required_fields [:url, :method, :flow_id, :contact_id, :organization_id]
  @optional_fields [:request_json, :response_json, :status_code, :request_headers, :error]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          url: String.t() | nil,
          method: String.t() | nil,
          request_json: map() | nil,
          response_json: map() | nil,
          status_code: non_neg_integer | nil,
          request_headers: [map()] | nil,
          error: String.t() | nil,
          flow_id: non_neg_integer | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          contact_id: non_neg_integer | nil,
          contact: Contact.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "webhook_logs" do
    field :url, :string
    field :method, :string
    field :request_json, :map, default: %{}

    field :response_json, :map, default: %{}
    field :status_code, :integer
    field :request_headers, {:array, :map}, default: []

    field :error, :string

    belongs_to :flow, Flow
    belongs_to :contact, Contact
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(WebhookLog.t(), map()) :: Ecto.Changeset.t()
  def changeset(webhook_log, attrs) do
    webhook_log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @doc """
  Create a Webhook Log
  """
  @spec create_webhook_log(map()) :: {:ok, WebhookLog.t()} | {:error, Ecto.Changeset.t()}
  def create_webhook_log(attrs \\ %{}) do
    %WebhookLog{}
    |> WebhookLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a Webhook Log
  """
  @spec update_webhook_log(WebhookLog.t(), map()) ::
          {:ok, WebhookLog.t()} | {:error, Ecto.Changeset.t()}
  def update_webhook_log(log, attrs) do
    log
    |> WebhookLog.changeset(attrs)
    |> Repo.update()
  end
end
