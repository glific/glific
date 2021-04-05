defmodule Glific.Partners.Billing do
  @moduledoc """
  We will use this as the main context interface for all billing subscriptions and the stripe
  interface.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Repo,
    Stats
  }

  alias Stripe.{Invoice, SubscriptionItem.Usage}

  # define all the required fields for
  @required_fields [
    :name,
    :email,
    :organization_id
  ]

  # define all the optional fields for organization
  @optional_fields [
    :stripe_customer_id,
    :stripe_payment_method_id,
    :stripe_subscription_id,
    :stripe_subscription_items,
    :stripe_current_period_start,
    :stripe_current_period_end,
    :stripe_last_usage_recorded,
    :currency,
    :is_delinquent,
    :is_active
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          stripe_customer_id: String.t() | nil,
          stripe_payment_method_id: String.t() | nil,
          stripe_subscription_id: String.t() | nil,
          stripe_subscription_items: map(),
          stripe_current_period_start: DateTime.t() | nil,
          stripe_current_period_end: DateTime.t() | nil,
          stripe_last_usage_recorded: DateTime.t() | nil,
          name: String.t() | nil,
          email: String.t() | nil,
          currency: String.t() | nil,
          is_delinquent: boolean,
          is_active: boolean() | true,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "billings" do
    field :stripe_customer_id, :string
    field :stripe_payment_method_id, :string

    field :stripe_subscription_id, :string
    field :stripe_subscription_items, :map, default: %{}

    field :stripe_current_period_start, :utc_datetime
    field :stripe_current_period_end, :utc_datetime
    field :stripe_last_usage_recorded, :utc_datetime

    field :name, :string
    field :email, :string
    field :currency, :string

    field :is_delinquent, :boolean, default: false
    field :is_active, :boolean, default: true

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Billing.t(), map()) :: Ecto.Changeset.t()
  def changeset(billing, attrs) do
    billing
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:stripe_customer_id)
  end

  @doc """
  Create a billing record
  """
  @spec create_billing(map()) :: {:ok, Billing.t()} | {:error, Ecto.Changeset.t()}
  def create_billing(attrs \\ %{}) do
    organization_id = Repo.get_organization_id()
    # update is_active = false for all the previous billing
    # records for this organizations
    Billing
    |> where([b], b.organization_id == ^organization_id)
    |> where([b], b.is_active == true)
    |> Repo.update_all(set: [is_active: false])

    %Billing{}
    |> Billing.changeset(Map.put(attrs, :organization_id, organization_id))
    |> Repo.insert()
  end

  @doc """
  Retrieve a billing record by clauses
  """
  @spec get_billing(map()) :: Billing.t() | nil
  def get_billing(clauses), do: Repo.get_by(Billing, clauses)

  @doc """
  Upate the billing record
  """
  @spec update_billing(Billing.t(), map()) ::
          {:ok, Billing.t()} | {:error, Ecto.Changeset.t()}
  def update_billing(%Billing{} = billing, attrs) do
    billing
    |> Billing.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete the billing record
  """
  @spec delete_billing(Billing.t()) ::
          {:ok, Billing.t()} | {:error, Ecto.Changeset.t()}
  def delete_billing(%Billing{} = billing) do
    Repo.delete(billing)
  end

  @doc """
  Create a billing record in glific, a billing customer in Stripe, given an organization
  """
  @spec create(Organization.t(), map()) ::
          {:ok, Billing.t()} | {:error, Ecto.Changeset.t() | String.t()}
  def create(organization, attrs) do
    case check_required(attrs) do
      {:error, error} -> {:error, error}
      _ -> do_create(organization, attrs)
    end
  end

  @spec do_create(Organization.t(), map()) :: {:ok, Billing.t()} | {:error, Ecto.Changeset.t()}
  defp do_create(organization, attrs) do
    {:ok, stripe_customer} =
      %{
        name: attrs.name,
        email: attrs.email,
        metadata: %{
          "id" => Integer.to_string(organization.id),
          "name" => organization.name
        }
      }
      |> Stripe.Customer.create()

    create_billing(
      attrs
      |> Map.put(:organization_id, organization.id)
      |> Map.put(:stripe_customer_id, stripe_customer.id)
    )
  end

  @spec check_stripe_key(list()) :: list()
  defp check_stripe_key(errors) do
    case Application.fetch_env(:stripity_stripe, :api_key) do
      {:ok, _} -> errors
      _ -> ["Stripe API Key not present" | errors]
    end
  end

  @spec format_errors(list()) :: :ok | {:error, String.t()}
  defp format_errors([]), do: :ok
  defp format_errors(list), do: {:error, Enum.join(list, ", ")}

  # We dont know what to do with billing currency as yet, but we'll figure it out soon
  # In Stripe, one contact can only have one currency
  @spec check_required(map()) :: :ok | {:error, String.t()}
  defp check_required(attrs) do
    [:name, :email, :currency]
    |> Enum.reduce(
      [],
      fn field, acc ->
        value = Map.get(attrs, field)

        if is_nil(value) || value == "",
          do: ["#{field} is not set" | acc],
          else: acc
      end
    )
    |> check_stripe_key()
    |> format_errors()
  end

  @spec stripe_ids :: map()
  defp stripe_ids,
    do: stripe_ids(Application.get_env(:glific, :environment))

  @spec stripe_ids(atom()) :: map()
  defp stripe_ids(:prod),
    do: %{}

  defp stripe_ids(_env),
    do: %{
      product: "prod_JETOZDWSMNMzwq",
      setup: "price_0Ic0S6ZVZ2O8W9YsphGSSTpn",
      monthly: "price_0Ic0S6ZVZ2O8W9Ys6BcEGNEm",
      users: "price_0Ic0S6ZVZ2O8W9YsfnQRPyB5",
      messages: "price_0Ic0S6ZVZ2O8W9YstRMIqHjg",
      consulting_hours: "price_0Ic0S6ZVZ2O8W9YsnZujHtBY"
    }

  @doc """
  Fetch the stripe id's
  """
  @spec get_stripe_ids :: map()
  def get_stripe_ids,
    do: stripe_ids()

  @spec subscription_params(Organization.t(), Billing.t()) :: map()
  defp subscription_params(organization, billing) do
    prices = stripe_ids()

    %{
      customer: billing.stripe_customer_id,
      items: [
        %{
          price: prices.monthly,
          quantity: 1
        },
        %{
          price: prices.users
        },
        %{
          price: prices.messages
        },
        %{
          price: prices.consulting_hours
        }
      ],
      metadata: %{
        "id" => Integer.to_string(billing.organization_id),
        "name" => organization.name
      }
    }
  end

  @doc """
  Update organization and stripe customer with the current payment method as returned
  by stripe
  """
  @spec update_payment_method(Organization.t(), String.t()) ::
          {:ok, Billing.t()} | {:error, Ecto.Changeset.t()}
  def update_payment_method(organization, stripe_payment_method_id) do
    # get the billing record
    billing = Repo.get_by!(Billing, %{organization_id: organization.id, is_active: true})

    # first update the contact with default payment id
    {:ok, _customer} =
      Stripe.Customer.update(
        billing.stripe_customer_id,
        %{
          invoice_settings: %{
            default_payment_method: stripe_payment_method_id
          }
        }
      )

    update_billing(
      billing,
      %{stripe_payment_method_id: stripe_payment_method_id}
    )
  end

  @doc """
  Once the organization has entered a new payment card we create a subscription for it.
  We'll do updating the card in a seperate function
  """
  @spec create_subscription(Organization.t(), String.t()) ::
          {:ok, Organization.t()} | {:pending, map()} | {:error, String.t()}
  def create_subscription(organization, stripe_payment_method_id) do
    # get the billing record
    billing = Repo.get_by!(Billing, %{organization_id: organization.id, is_active: true})

    {:ok, _} = update_payment_method(organization, stripe_payment_method_id)

    setup(organization, billing)

    attach_payment_method(billing)

    subscription(organization, billing)
  end

  @spec attach_payment_method(Billing.t()) :: {:ok, Stripe.PaymentMethod.t()}
  defp attach_payment_method(billing) do
    Stripe.PaymentMethod.attach(%{
      customer: billing.stripe_customer_id,
      payment_method: billing.stripe_payment_method_id
    })
  end

  @spec setup(Organization.t(), Billing.t()) :: :ok
  defp setup(organization, billing) do
    {:ok, _invoice_item} =
      Stripe.Invoiceitem.create(%{
        customer: billing.stripe_customer_id,
        currency: billing.currency,
        price: stripe_ids().setup,
        metadata: %{
          "id" => Integer.to_string(organization.id),
          "name" => organization.name
        }
      })

    {:ok, _invoice} =
      Stripe.Invoice.create(%{
        customer: billing.stripe_customer_id,
        auto_advance: true,
        collection_method: "charge_automatically",
        metadata: %{
          "id" => Integer.to_string(organization.id),
          "name" => organization.name
        }
      })

    :ok
  end

  @spec subscription(Organization.t(), Billing.t()) ::
          {:ok, Organization.t()} | {:pending, map()} | {:error, String.t()}
  defp subscription(organization, billing) do
    # now create and attach the subscriptions to this organization
    params = subscription_params(organization, billing)
    opts = [expand: ["latest_invoice.payment_intent", "pending_setup_intent"]]

    case Stripe.Subscription.create(params, opts) do
      # subscription is active, we need to update the same information via the
      # webhook call 'invoice.paid' also, so might need to refactor this at
      # a later date
      {:ok, subscription} ->
        # if subscription requires client intervention (most likely for India, we need this)
        # we need to send back info to the frontend
        cond do
          subscription.status == "incomplete" &&
            !is_nil(subscription.pending_setup_intent) &&
              subscription.pending_setup_intent.status == "required_action" ->
            {
              :pending,
              %{
                organization: organization,
                client_secret: subscription.pending_setup_intent.client_secret
              }
            }

          subscription.status == "active" ->
            params =
              %{}
              |> Map.merge(subscription |> subscription_details())
              |> Map.merge(subscription |> subscription_dates())
              |> Map.merge(subscription |> subscription_items())

            update_billing(billing, params)

          true ->
            {:error, "Not handling #{inspect(subscription)} value"}
            {:ok, organization}
        end

      {:error, stripe_error} ->
        {:error, inspect(stripe_error)}
    end
  end

  # return a map which maps glific product ids to subscription item ids
  @spec subscription_details(Stripe.Subscription.t()) :: map()
  defp subscription_details(subscription),
    do: %{
      stripe_subscription_id: subscription.id,
      is_delinquent: false
    }

  @spec subscription_dates(Stripe.Subscription.t()) :: map()
  defp subscription_dates(subscription) do
    period_start = DateTime.from_unix!(subscription.current_period_start)
    period_end = DateTime.from_unix!(subscription.current_period_end)

    %{
      stripe_current_period_start: period_start,
      stripe_current_period_end: period_end,
      stripe_last_usage_recorded: period_start
    }
  end

  # return a map which maps glific product ids to subscription item ids
  @spec subscription_items(Stripe.Subscription.t()) :: map()
  defp subscription_items(%{items: items} = _subscription) do
    items.data
    |> Enum.reduce(
      %{},
      fn item, acc ->
        Map.put(acc, item.price.id, item.id)
      end
    )
    |> (fn v -> %{stripe_subscription_items: v} end).()
  end

  # get dates and times in the right format for other functions
  @spec format_dates(DateTime.t(), DateTime.t()) ::
          {Date.t(), Date.t(), DateTime.t(), non_neg_integer}
  defp format_dates(start_date, end_date) do
    end_usage_datetime =
      end_date
      |> Timex.shift(days: -1)
      |> Timex.end_of_day()

    {
      start_date |> DateTime.to_date(),
      end_usage_datetime |> DateTime.to_date(),
      end_usage_datetime,
      end_usage_datetime |> DateTime.to_unix()
    }
  end

  @doc """
  Record the usage for a specific organization
  """
  @spec record_usage(non_neg_integer, DateTime.t(), DateTime.t()) :: :ok
  def record_usage(organization_id, start_date, end_date) do
    # get the billing record
    billing = Repo.get_by!(Billing, %{organization_id: organization_id, is_active: true})

    {start_usage_date, end_usage_date, end_usage_datetime, time} =
      format_dates(start_date, end_date)

    case Stats.usage(organization_id, start_usage_date, end_usage_date) do
      # temp fix for testing, since we dont really have any data streaming into our DB
      # to test for invoices
      _usage ->
        usage = %{messages: Enum.random(10..500), users: Enum.random(1..50)}

        prices = stripe_ids()
        subscription_items = billing.stripe_subscription_items

        record_subscription_item(
          subscription_items[prices.messages],
          usage.messages,
          time,
          "messages: #{organization_id}, #{Date.to_string(start_usage_date)}"
        )

        record_subscription_item(
          subscription_items[prices.users],
          usage.users,
          time,
          "users: #{organization_id}, #{Date.to_string(start_usage_date)}"
        )

        {:ok, _} = update_billing(billing, %{stripe_last_usage_recorded: end_usage_datetime})
    end

    :ok
  end

  # record the usage against a subscription item in stripe
  @spec record_subscription_item(String.t(), pos_integer, pos_integer, String.t()) :: nil
  defp record_subscription_item(subscription_item_id, quantity, time, idempotency) do
    {:ok, _} =
      Usage.create(
        subscription_item_id,
        %{
          quantity: quantity,
          timestamp: time
        },
        idempotency_key: idempotency
      )

    nil
  end

  @doc """
  Finalize a draft invoice
  """
  @spec finalize_invoice(String.t()) :: {:ok, t()} | {:error, Stripe.Error.t()}
  def finalize_invoice(invoice_id),
    do: Invoice.finalize(invoice_id, %{})

  # events that we need to handle, delete comment once handled :)
  # invoice.upcoming
  # invoice.created - send final usage record here, also send on a weekly basis, to avoid error
  # invoice.paid
  # invoice.payment_failed
  # invoice.payment_action_required
end
