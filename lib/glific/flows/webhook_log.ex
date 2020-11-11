defmodule Glific.Flows.WebhookLog do
  @moduledoc """
  The webhook log object
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    Flows.Flow,
    Partners.Organization,
    Repo
  }

  @required_fields [:request_json, :flow_id, :flow_uuid, :organization_id]
  @optional_fields [:response_json]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          request_json: map() | nil,
          response_json: map() | nil,
          flow_id: non_neg_integer | nil,
          flow_uuid: Ecto.UUID.t() | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "webhook_logs" do
    field :request_json, :map, default: %{}
    field :response_json, :map, default: %{}

    field :flow_uuid, Ecto.UUID
    belongs_to :flow, Flow
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
