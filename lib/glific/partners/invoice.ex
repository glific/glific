defmodule Glific.Partners.Invoice do
  @moduledoc """
  Invoice model wrapper
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Glific.{Partners, Partners.Billing, Partners.Organization, Repo}
  alias __MODULE__

  @required_fields [
    :customer_id,
    :invoice_id,
    :start_date,
    :end_date,
    :status,
    :amount,
    :organization_id,
    :line_items
  ]
  @optional_fields [:users, :messages, :consulting_hours]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          customer_id: String.t() | nil,
          invoice_id: String.t() | nil,
          start_date: :utc_datetime_usec | nil,
          end_date: :utc_datetime_usec | nil,
          status: String.t() | nil,
          amount: integer,
          line_items: map(),
          users: integer,
          messages: integer,
          consulting_hours: integer,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "invoices" do
    field :customer_id, :string
    field :invoice_id, :string
    field :start_date, :utc_datetime_usec
    field :end_date, :utc_datetime_usec
    field :status, :string
    field :amount, :integer, default: 0
    field :users, :integer, default: 0
    field :messages, :integer, default: 0
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
  def create_invoice(%{stripe_invoice: invoice, organization_id: organization_id} = _attrs) do
    start_date = DateTime.from_unix!(invoice.period_start)
    end_date = DateTime.from_unix!(invoice.period_end)
    org = Partners.get_organization!(organization_id)

    attrs = %{
      customer_id: invoice.customer,
      invoice_id: invoice.id,
      organization_id: organization_id,
      status: "open",
      amount: invoice.amount_due,
      start_date: start_date,
      end_date: end_date
    }

    line_items =
      invoice.lines.data
      |> Enum.reduce(%{}, fn line, acc ->
        Map.put(acc, line.price.id, %{
          nickname: line.price.nickname,
          start_date: DateTime.from_unix!(line.period.start),
          end_date: DateTime.from_unix!(line.period.end)
        })
      end)

    attrs = Map.put(attrs, :line_items, line_items)

    {:ok, invoice} = create_invoice(attrs)

    stripe_ids = Billing.get_stripe_ids()

    case line_items[stripe_ids.setup] do
      nil ->
        Billing.record_usage(
          org,
          line_items[stripe_ids.messages].start_date,
          line_items[stripe_ids.messages].end_date
        )

      _ ->
        :ok
    end

    {:ok, invoice}
  end

  def create_invoice(attrs) do
    %Invoice{}
    |> Invoice.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Fetch an invoice record by stripe invoice id
  """
  @spec fetch_invoice(non_neg_integer) :: Invoice.t() | nil
  def fetch_invoice(invoice_id), do: Repo.get_by(Invoice, invoice_id: invoice_id)

  @doc """
  Return the count of invoices, based on filters
  """
  @spec count_invoices(map()) :: integer
  def count_invoices(args),
    do: Repo.count_filter(args, Invoice, &filter_with/2)

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:status, status}, query ->
        from q in query, where: q.status == ^status

      _, query ->
        query
    end)
  end

  @doc """
  Update an invoice record
  """
  @spec update_invoice(Invoice.t(), map()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def update_invoice(%Invoice{} = invoice, attrs) do
    invoice
    |> Invoice.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Update the status of an invoice
  """
  @spec update_invoice_status(non_neg_integer, String.t()) :: {:ok | :error, String.t()}
  def update_invoice_status(invoice_id, status) do
    case fetch_invoice(invoice_id) do
      %Invoice{id: _} = invoice ->
        update_invoice(invoice, %{status: status})
        billing = Billing.get_billing(%{organization_id: invoice.organization_id})

        unpaid_invoice_count =
          count_invoices(%{
            filter: %{status: "payment_failed", organization_id: invoice.organization_id}
          })

        is_delinquent =
          if status == "payment_failed" or unpaid_invoice_count != 0, do: true, else: false

        case Billing.update_billing(billing, %{is_delinquent: is_delinquent}) do
          {:ok, _} ->
            {:ok, "Invoice status updated for #{invoice_id}"}

          {:error, error} ->
            {:error, "Error updating status for #{invoice_id}, Errors: #{inspect(error)}"}
        end

      nil ->
        # Need to log this so we know what happended and why
        {:ok, "Could not find invoice for #{invoice_id}"}
    end
  end
end
