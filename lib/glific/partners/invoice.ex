defmodule Glific.Partners.Invoice do
  @moduledoc """
  Invoice model wrapper
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Glific.{Partners.Organization, Repo}
  alias __MODULE__

  import Ecto.Query, warn: false

  @required_fields [
    :invoice_id,
    :invoice_start_date,
    :invoice_end_date,
    :status,
    :amount,
    :organization_id,
    :line_items
  ]
  @optional_fields [:user_usage, :message_usage, :consulting_hours]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          invoice_id: String.t() | nil,
          invoice_start_date: :utc_datetime_usec | nil,
          invoice_end_date: :utc_datetime_usec | nil,
          status: String.t() | nil,
          amount: integer,
          line_items: map(),
          user_usage: integer,
          message_usage: integer,
          consulting_hours: integer,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "invoices" do
    field :invoice_id, :string
    field :invoice_start_date, :utc_datetime_usec
    field :invoice_end_date, :utc_datetime_usec
    field :status, :string
    field :amount, :integer, default: 0
    field :user_usage, :integer, default: 0
    field :message_usage, :integer, default: 0
    field :consulting_hours, :integer, default: 0
    field :line_items, :map, default: %{}

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Invoice.t(), map()) :: Ecto.Changeset.t()
  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:invoice_id)
    |> foreign_key_constraint(:organization_id)
  end

  @doc """
  Create an invoice record
  """
  @spec create_invoice(map()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def create_invoice(attrs \\ %{}) do
    %Invoice{}
    |> Invoice.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Fetch an invoice record
  """
  @spec fetch_invoice!(non_neg_integer) :: Invoice.t()
  def fetch_invoice!(invoice_id), do: Repo.get_by!(Invoice, invoice_id: invoice_id)

  @doc """
  Update an invoice record
  """
  @spec update_invoice(Invoice.t(), map()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def update_invoice(%Invoice{} = invoice, attrs) do
    invoice
    |> Invoice.changeset(attrs)
    |> Repo.update()
  end
end
