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

  @required_fields [:url, :method, :request_headers, :flow_id, :contact_id, :organization_id]
  @optional_fields [:request_json, :response_json, :status_code, :error]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          url: String.t() | nil,
          method: String.t() | nil,
          request_headers: map() | nil,
          request_json: map() | nil,
          response_json: map() | nil,
          status_code: non_neg_integer | nil,
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
    field :request_headers, :map, default: %{}
    field :request_json, :map, default: %{}

    field :response_json, :map, default: %{}
    field :status_code, :integer

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

  @doc """
  Returns the list of webhook_logs.
  Since this is very basic and only listing funcatinality we added the status filter like this. 
  In future we will put the status as virtual filed in the webhook logs itself.
  """
  @spec list_webhook_logs(map()) :: [WebhookLog.t()]
  def list_webhook_logs(args) do
    webhook_logs = Repo.list_filter(args, WebhookLog, &Repo.opts_with_inserted_at/2, &filter_with/2)
    Enum.map(webhook_logs, fn webhook_log -> webhook_log|> Map.put(:status, get_status(webhook_log.status_code)) end)
  end

  def get_status(status) when status in 100..199, do: "Informational response"
  def get_status(status) when status in 200..299, do: "Success"
  def get_status(status) when status in 300..399, do: "Redirect"
  def get_status(status) when status in 400..599, do: "Error"
  def get_status(_), do: "Undefined"

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:url, url}, query ->
        from q in query, where: q.url == ^url

      {:status_code, status_code}, query ->
        from q in query, where: q.status_code == ^status_code

      _, query ->
        query
    end)
  end

  @doc """
  Return the count of webhook_logs, using the same filter as list_webhook_logs
  """
  @spec count_webhook_logs(map()) :: integer
  def count_webhook_logs(args),
    do: Repo.count_filter(args, WebhookLog, &filter_with/2)
end
