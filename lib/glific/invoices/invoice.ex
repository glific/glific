defmodule Glific.Invoices.Invoice do
  @moduledoc """
  Invoice model wrapper
  """
  use Ecto.Schema

  alias Glific.{Invoices.Invoice, Partners.Organization}

  import Ecto.Changeset

  @required_fields [
    :invoice_id,
    :invoice_start_date,
    :invoice_end_date,
    :status,
    :amount,
    :organization_id
  ]
  @optional_fields [:user_usage, :message_usage, :consulting_hours]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          invoice_id: String.t() | nil,
          invoice_start_date: :utc_datetime_usec | nil,
          invoice_end_date: :utc_datetime_usec | nil,
          status: String.t() | nil,
          amount: :integer | nil,
          user_usage: :integer | nil,
          message_usage: :integer | nil,
          consulting_hours: :integer | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "users" do
    field :invoice_id, :string
    field :invoice_start_date, :utc_datetime_usec
    field :invoice_end_date, :utc_datetime_usec
    field :status, :string
    field :amount, :integer
    field :user_usage, :integer, default: 0
    field :message_usage, :integer, default: 0
    field :consulting_hours, :integer, default: 0

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
end
