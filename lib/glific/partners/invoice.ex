defmodule Glific.Partners.Invoice do
  @moduledoc """
  Invoice model wrapper
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false
  import GlificWeb.Gettext

  alias Glific.{Partners.Billing, Partners.Organization, Repo}
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

  @spec invoice_attrs(map(), non_neg_integer) :: map()
  defp invoice_attrs(invoice, organization_id),
    do: %{
      customer_id: invoice.customer,
      invoice_id: invoice.id,
      organization_id: organization_id,
      status: invoice.status,
      amount: invoice.amount_due,
      start_date: DateTime.from_unix!(invoice.period_start),
      end_date: DateTime.from_unix!(invoice.period_end)
    }

  @spec setup?(String.t() | nil) :: boolean()
  defp setup?(nil), do: false
  defp setup?(str), do: String.contains?(String.downcase(str), "setup")

  @spec line_items(map(), map()) :: {map(), boolean}
  defp line_items(attrs, invoice) do
    {line_items, setup} =
      invoice.lines.data
      |> Enum.reduce(
        {%{}, false},
        fn line, {acc, setup} ->
          acc =
            Map.put(acc, line.price.id, %{
              nickname: line.price.nickname,
              start_date: DateTime.from_unix!(line.period.start),
              end_date: DateTime.from_unix!(line.period.end)
            })

          setup = setup || setup?(line.price.nickname)
          {acc, setup}
        end
      )

    {
      Map.put(attrs, :line_items, line_items),
      setup
    }
  end

  @spec invoice({map(), boolean}, map()) :: {Invoice.t(), boolean}
  defp invoice({attrs, setup}, _) do
    invoice =
      case fetch_invoice(%{invoice_id: attrs.invoice_id}) do
        nil ->
          {:ok, invoice} = create_invoice(attrs)
          invoice

        invoice ->
          update_invoice(
            invoice,
            %{status: attrs.status, line_items: attrs.line_items}
          )
      end

    {invoice, setup}
  end

  @spec finalize({Invoice.t(), boolean}) :: Invoice.t()
  defp finalize({invoice, setup}) do
    if setup do
      # Finalizing a draft invoice
      case Stripe.Invoice.finalize(invoice.invoice_id, %{}) do
        {:ok, _} ->
          invoice

        {:error, error} ->
          {:error,
           dgettext("errors", "Error occurred while finalizing setup invoice: %{error}",
             error: inspect(error)
           )}
      end
    end

    invoice
  end

  @spec finalize(Invoice.t()) :: Invoice.t() | nil
  defp update_prorations(invoice) do
    billing = Billing.get_billing(%{organization_id: invoice.organization_id})
    # our test record does not have a billing, need to clean that up
    if billing != nil && billing.stripe_subscription_id != nil do
      {:ok, _} = Stripe.Subscription.update(billing.stripe_subscription_id, %{prorate: true})
      invoice
    else
      nil
    end
  end

  @doc """
  Create an invoice record
  """
  @spec create_invoice(map()) :: {:ok, Invoice.t()} | {:error, String.t()}
  def create_invoice(%{stripe_invoice: invoice, organization_id: organization_id} = _attrs) do
    invoice =
      invoice
      |> invoice_attrs(organization_id)
      |> line_items(invoice)
      |> invoice(invoice)
      |> finalize()
      # Temporary, for the existing customers prorations to be updated.
      |> update_prorations()

    if invoice,
      do: {:ok, invoice},
      else: {:error, dgettext("errors", "Could not create invoice")}
  end

  def create_invoice(attrs) do
    %Invoice{}
    |> Invoice.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Fetch an invoice record by clauses
  """
  @spec fetch_invoice(map()) :: Invoice.t() | nil
  def fetch_invoice(clauses), do: Repo.get_by(Invoice, clauses)

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
  @spec update_invoice(Invoice.t(), map()) :: Invoice.t() | {:error, Ecto.Changeset.t()}
  def update_invoice(%Invoice{} = invoice, attrs) do
    {:ok, invoice} =
      invoice
      |> Invoice.changeset(attrs)
      |> Repo.update()

    invoice
  end

  @spec update_delinquency(Invoice.t()) :: {:ok, Billing.t()} | {:error, map()}
  defp update_delinquency(invoice) do
    billing = Billing.get_billing(%{organization_id: invoice.organization_id})

    unpaid_invoice_count =
      count_invoices(%{
        filter: %{status: "payment_failed", organization_id: invoice.organization_id}
      })

    is_delinquent =
      if invoice.status == "payment_failed" or unpaid_invoice_count != 0, do: true, else: false

    Billing.update_billing(billing, %{is_delinquent: is_delinquent})
  end

  @doc """
  Update the status of an invoice
  """
  @spec update_invoice_status(non_neg_integer, String.t()) :: {:ok | :error, String.t()}
  def update_invoice_status(invoice_id, status) do
    case fetch_invoice(%{invoice_id: invoice_id}) do
      %Invoice{id: _} = invoice ->
        result =
          invoice
          |> update_invoice(%{status: status})
          |> update_delinquency

        case result do
          {:ok, _} ->
            {:ok,
             dgettext(
               "errors",
               "Invoice status updated for %{invoice_id}",
               invoice_id: invoice_id
             )}

          {:error, error} ->
            {:error,
             dgettext(
               "errors",
               "Error occurred while updating status for %{invoice_id}: %{error}",
               invoice_id: invoice_id,
               error: inspect(error)
             )}
        end

      nil ->
        # Need to log this so we know what happended and why
        {:ok,
         dgettext("errors", "Could not find invoice for %{invoice_id}", invoice_id: invoice_id)}
    end
  end
end
