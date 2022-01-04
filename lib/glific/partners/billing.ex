defmodule Glific.Partners.Billing do
  @moduledoc """
  We will use this as the main context interface for all billing subscriptions and the stripe
  interface.
  """

  use Ecto.Schema
  use Publicist
  import Ecto.Changeset
  import Ecto.Query, warn: false
  import GlificWeb.Gettext

  alias __MODULE__

  require Logger

  alias Glific.{
    Partners,
    Partners.Organization,
    Partners.Saas,
    Repo,
    Saas.ConsultingHour,
    Stats
  }

  alias Stripe.{
    BillingPortal,
    Request,
    Subscription,
    SubscriptionItem,
    SubscriptionItem.Usage
  }

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
    :stripe_subscription_status,
    :stripe_current_period_end,
    :stripe_last_usage_recorded,
    :currency,
    :is_delinquent,
    :is_active,
    :deduct_tds,
    :tds_amount
  ]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          stripe_customer_id: String.t() | nil,
          stripe_payment_method_id: String.t() | nil,
          stripe_subscription_id: String.t() | nil,
          stripe_subscription_status: String.t() | nil,
          stripe_subscription_items: map(),
          stripe_current_period_start: DateTime.t() | nil,
          stripe_current_period_end: DateTime.t() | nil,
          stripe_last_usage_recorded: DateTime.t() | nil,
          name: String.t() | nil,
          email: String.t() | nil,
          currency: String.t() | nil,
          is_delinquent: boolean,
          is_active: boolean() | true,
          deduct_tds: boolean() | false,
          tds_amount: float() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "billings" do
    field :stripe_customer_id, :string
    field :stripe_payment_method_id, :string

    field :stripe_subscription_id, :string
    field :stripe_subscription_status, :string
    field :stripe_subscription_items, :map, default: %{}

    field :stripe_current_period_start, :utc_datetime
    field :stripe_current_period_end, :utc_datetime
    field :stripe_last_usage_recorded, :utc_datetime

    field :name, :string
    field :email, :string
    field :currency, :string

    field :is_delinquent, :boolean, default: false
    field :is_active, :boolean, default: true

    field :deduct_tds, :boolean, default: false

    field :tds_amount, :float

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
  def get_billing(clauses), do: Repo.get_by(Billing, clauses, skip_organization_id: true)

  @doc """
  Upate the billing record
  """
  @spec update_billing(Billing.t(), map()) ::
          {:ok, Billing.t()} | {:error, Ecto.Changeset.t()}
  def update_billing(%Billing{} = billing, attrs) do
    billing
    |> Billing.changeset(attrs)
    |> Repo.update(skip_organization_id: true)
  end

  @doc """
  Upate the stripe customer details record
  """
  @spec update_stripe_customer(Billing.t(), map()) ::
          {:ok, Billing.t()} | {:error, Stripe.Error.t()}
  def update_stripe_customer(%Billing{} = billing, attrs) do
    with {:ok, _customer} <-
           Stripe.Customer.update(
             billing.stripe_customer_id,
             Map.take(attrs, [:email, :name])
           ) do
      {:ok, billing}
    end
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

  @doc """
  Fetch the stripe id's
  """
  @spec stripe_ids :: map()
  def stripe_ids,
    do: Saas.stripe_ids()

  @doc """
  Fetch the stripe tax rates
  """
  @spec tax_rates :: list()
  def tax_rates,
    do: Saas.tax_rates()

  @spec subscription_params(Billing.t(), Organization.t()) :: map()
  defp subscription_params(billing, organization) do
    # Temporary to make sure that the subscription starts from the beginning of next month
    anchor_timestamp =
      DateTime.utc_now()
      |> Timex.end_of_month()
      |> Timex.shift(days: 1)
      |> Timex.beginning_of_day()
      |> DateTime.to_unix()

    prices = stripe_ids()

    %{
      customer: billing.stripe_customer_id,
      # Temporary for existing customers.
      billing_cycle_anchor: anchor_timestamp,
      prorate: false,
      items: [
        %{
          price: prices["users"]
        },
        %{
          price: prices["messages"]
        },
        %{
          price: prices["consulting_hours"]
        }
      ],
      metadata: %{
        "id" => Integer.to_string(billing.organization_id),
        "name" => organization.name
      },
      default_tax_rates: tax_rates()
    }
  end

  @doc """
  Update organization and stripe customer with the current payment method as returned
  by stripe
  """
  @spec update_payment_method(Organization.t(), String.t()) ::
          {:ok, Billing.t()} | {:error, map()}
  def update_payment_method(organization, stripe_payment_method_id) do
    # get the billing record
    billing = Repo.get_by!(Billing, %{organization_id: organization.id, is_active: true})
    # first update the contact with default payment id
    with {:ok, _res} <-
           Stripe.PaymentMethod.attach(%{
             customer: billing.stripe_customer_id,
             payment_method: stripe_payment_method_id
           }),
         {:ok, _customer} <-
           Stripe.Customer.update(billing.stripe_customer_id, %{
             invoice_settings: %{default_payment_method: stripe_payment_method_id}
           }) do
      update_billing(billing, %{stripe_payment_method_id: stripe_payment_method_id})
      |> send_update_response()
    end
  end

  @spec send_update_response(tuple()) :: {:ok, Billing.t()} | {:error, map()}
  defp send_update_response({:ok, billing}), do: {:ok, billing}
  defp send_update_response({:error, _}), do: {:error, %{message: "Error while saving details"}}

  @doc """
  Validate entered coupon code and return with coupon details
  """
  @spec get_promo_codes(any()) :: any()
  def get_promo_codes(code) do
    with {:ok, response} <- make_promocode_request(code) do
      make_results(response.data)
    end
  end

  defp make_results([]), do: {:error, "Invalid coupon code"}

  defp make_results(response) do
    result = List.first(response)

    coupon =
      %{code: result.code}
      |> Map.put(:metadata, result.coupon.metadata)
      |> Map.put(:id, result.coupon.id)

    {:ok, coupon}
  end

  defp make_promocode_request(code) do
    make_stripe_request("promotion_codes", :get, %{code: code})
  end

  @doc """
  Once the organization has entered a new payment card we create a subscription for it.
  We'll do updating the card in a seperate function
  """
  @spec create_subscription(Organization.t(), map()) ::
          {:ok, Stripe.Subscription.t()} | {:pending, map()} | {:error, String.t()}
  def create_subscription(organization, params) do
    stripe_payment_method_id = params.stripe_payment_method_id
    # get the billing record
    billing = Repo.get_by!(Billing, %{organization_id: organization.id, is_active: true})

    update_payment_method(organization, stripe_payment_method_id)
    |> case do
      {:ok, _} ->
        billing
        |> setup(organization, params)
        |> subscription(organization)

      {:error, error} ->
        Logger.info("Error while updating the card. #{inspect(error)}")
        {:error, error.message}
    end
  end

  @spec setup(Billing.t(), Organization.t(), map()) :: Billing.t()
  defp setup(billing, organization, params) do
    ## let's create an invocie items. We are not attaching this to the invoice
    ## so it will be attached automatically to the next invoice create.

    {:ok, invoice_item} =
      Stripe.Invoiceitem.create(%{
        customer: billing.stripe_customer_id,
        currency: billing.currency,
        price: stripe_ids()["setup"],
        tax_rates: tax_rates(),
        metadata: %{
          "id" => Integer.to_string(organization.id),
          "name" => organization.name
        }
      })

    apply_coupon(invoice_item.id, params)

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

    billing
  end

  @spec apply_coupon(String.t(), map()) :: nil | {:error, Stripe.Error.t()} | {:ok, any()}
  defp apply_coupon(invoice_item_id, %{coupon_code: coupon_code}) do
    make_stripe_request("invoiceitems/#{invoice_item_id}", :post, %{
      discounts: [%{coupon: coupon_code}]
    })
  end

  defp apply_coupon(_, _), do: nil

  @doc """
  Adding credit to customer in Stripe
  """
  @spec credit_customer(map()) :: any | non_neg_integer()
  def credit_customer(transaction) do
    with billing <-
           get_billing(%{organization_id: transaction.organization_id}),
         "draft" <- transaction.status,
         true <- billing.deduct_tds do
      credit = calculate_credit(billing, transaction)

      # Add credit to customer
      Stripe.CustomerBalanceTransaction.create(billing.stripe_customer_id, %{
        amount: -credit,
        currency: billing.currency
      })

      # Update invoice footer with message
      Stripe.Invoice.update(transaction.invoice_id, %{
        footer:
          "TDS INR #{(credit / 100) |> trunc()} for Month of #{DateTime.utc_now().month |> Timex.month_name()} deducted above under Applied Balance section"
      })

      credit
    end
  end

  # Calculate the amount to be credited to customer account
  @spec calculate_credit(Billing.t(), map()) :: non_neg_integer()
  defp calculate_credit(billing, transaction) do
    (billing.tds_amount / 100 * transaction.amount_due) |> trunc()
  end

  @doc """
  A common function for making Stripe API calls with params that are not supported withing Stripity Stripe
  """
  @spec make_stripe_request(String.t(), atom(), map(), list()) :: any()
  def make_stripe_request(endpoint, method, params, opts \\ []) do
    Request.new_request(opts)
    |> Request.put_endpoint(endpoint)
    |> Request.put_method(method)
    |> Request.put_params(params)
    |> Request.make_request()
  end

  @spec subscription(Billing.t(), Organization.t()) ::
          {:ok, Stripe.Subscription.t()} | {:pending, map()} | {:error, String.t()}
  defp subscription(billing, organization) do
    opts = [expand: ["latest_invoice.payment_intent", "pending_setup_intent"]]

    billing
    |> subscription_params(organization)
    |> Subscription.create(opts)
    |> case do
      # subscription is active, we need to update the same information via the
      # webhook call 'invoice.paid' also, so might need to refactor this at
      # a later date

      {:ok, subscription} ->
        update_subscription_details(subscription, organization.id, billing)
        # if subscription requires client intervention (most likely for India, we need this)
        # we need to send back info to the frontend
        cond do
          subscription_requires_auth?(subscription) ->
            {:pending,
             %{
               status: :pending,
               organization: organization,
               client_secret: subscription.pending_setup_intent.client_secret
             }}

          subscription.status == "active" ->
            ## we can add more field as per our need
            {:ok, %{status: :active}}

          true ->
            {:error,
             dgettext("errors", "Not handling %{return} value", return: inspect(subscription))}
        end

      {:error, stripe_error} ->
        {:error, inspect(stripe_error)}
    end
  end

  @doc """
  Update organization subscription plan
  """
  @spec update_subscription(Billing.t(), Organization.t()) :: Organization.t()
  def update_subscription(billing, %{status: :suspended} = organization) do
    billing.stripe_subscription_items
    |> Map.values()
    |> Enum.each(fn subscription_item ->
      SubscriptionItem.delete(subscription_item, %{clear_usage: false}, [])
    end)

    params = %{
      proration_behavior: "create_prorations",
      items: [
        %{
          price: stripe_ids()["inactive"],
          quantity: 1,
          tax_rates: tax_rates()
        }
      ],
      metadata: %{
        "id" => Integer.to_string(billing.organization_id),
        "name" => organization.name
      }
    }

    SubscriptionItem.delete(
      billing.stripe_subscription_items[stripe_ids()["monthly"]],
      %{},
      []
    )

    Stripe.Subscription.update(billing.stripe_subscription_id, params, [])
    organization
  end

  def update_subscription(billing, %{status: status} = organization)
      when status in [:inactive, :ready_to_delete] do
    ## let's delete the subscription by end of that month and deactivate the
    ## billing when we change the status to inactive and ready to delete.
    Stripe.Subscription.delete(billing.stripe_customer_id, %{at_period_end: true})
    update_billing(billing, %{is_active: false})
    organization
  end

  def update_subscription(_billing, organization), do: organization

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
      stripe_current_period_end: period_end
    }
  end

  # return a map which maps glific product ids to subscription item ids
  @spec subscription_items(Stripe.Subscription.t()) :: map()
  defp subscription_items(%{items: items} = _subscription) do
    v =
      items.data
      |> Enum.reduce(
        %{},
        fn item, acc ->
          Map.put(acc, item.price.id, item.id)
        end
      )

    %{stripe_subscription_items: v}
  end

  # return a map which maps glific product ids to subscription item ids
  @spec subscription_status(Stripe.Subscription.t()) :: map()
  defp subscription_status(subscription) do
    cond do
      subscription_requires_auth?(subscription) ->
        %{stripe_subscription_status: "pending"}

      subscription.status == "active" ->
        %{stripe_subscription_status: "active"}

      true ->
        %{stripe_subscription_status: "pending"}
    end
  end

  # function to check if the subscription requires another authentcation i.e 3D
  @spec subscription_requires_auth?(Stripe.Subscription.t()) :: boolean()
  defp subscription_requires_auth?(%{pending_setup_intent: pending_setup_intent})
       when is_map(pending_setup_intent),
       do: Map.get(pending_setup_intent, :status, "") == "requires_action"

  defp subscription_requires_auth?(_subscription), do: false

  @doc """
  Update subscription details. We will also use this method while updating the details form webhook.
  """
  @spec update_subscription_details(Stripe.Subscription.t(), non_neg_integer(), Billing.t() | nil) ::
          {:ok, Stripe.Subscription.t()} | {:error, String.t()}
  def update_subscription_details(subscription, organization_id, nil) do
    Repo.fetch_by(Billing, %{
      stripe_subscription_id: subscription.id,
      organization_id: organization_id
    })
    |> case do
      {:ok, billing} ->
        update_subscription_details(subscription, organization_id, billing)

      _ ->
        Logger.info(
          "Error while updating the subscription details for subscription #{subscription.id} and organization_id: #{organization_id}"
        )

        message = """
        Did not find Billing object for Subscription: #{subscription.id}, org: #{organization_id}
        """

        {:error, message}
    end
  end

  def update_subscription_details(subscription, _organization_id, billing) do
    params =
      %{}
      |> Map.merge(subscription |> subscription_details())
      |> Map.merge(subscription |> subscription_dates())
      |> Map.merge(subscription |> subscription_items())
      |> Map.merge(subscription |> subscription_status())

    update_billing(billing, params)
    {:ok, subscription}
  end

  @doc """
    Stripe subscription created callback via webhooks.
    We are using this to update the prorate data with monthly billing.
  """
  @spec subscription_created_callback(Stripe.Subscription.t(), non_neg_integer()) ::
          :ok | {:error, Stripe.Error.t()}
  def subscription_created_callback(subscription, org_id) do
    ## we can not add prorate for 3d secure cards. That's why we are using the
    ## subscription created callback to add the monthly subscription with prorate
    ## data.

    with billing <- get_billing(%{organization_id: org_id}),
         false <- billing.stripe_subscription_items |> Map.has_key?(stripe_ids()["monthly"]) do
      proration_date = DateTime.utc_now() |> DateTime.to_unix()

      make_stripe_request("subscription_items", :post, %{
        subscription: subscription.id,
        prorate: true,
        proration_date: proration_date,
        price: stripe_ids()["monthly"],
        quantity: 1
      })
    else
      _ -> {:ok, subscription}
    end
  end

  # get dates and times in the right format for other functions
  @spec format_dates(DateTime.t(), DateTime.t()) :: map()
  defp format_dates(start_date, end_date) do
    end_date = end_date |> Timex.end_of_day()

    %{
      start_usage_date: start_date |> DateTime.to_date(),
      end_usage_date: end_date |> DateTime.to_date(),
      end_usage_datetime: end_date,
      time: end_date |> DateTime.to_unix()
    }
  end

  @doc """
  Update the usage record for all active subscriptions on a daily and weekly basis
  """
  @spec update_usage(non_neg_integer, map()) :: :ok
  def update_usage(_organization_id, %{time: time}) do
    record_date = time |> Timex.end_of_day()

    # if record date is sunday, we need to record previous weeks usage
    # or if it is the end of month then record usage for the remaining days of week
    if Date.day_of_week(record_date) == 7 ||
         Timex.days_in_month(record_date) - record_date.day == 0,
       do: period_usage(record_date)

    :ok
  end

  @doc """
  This is called on a regular schedule to update usage.
  """
  @spec period_usage(DateTime.t()) :: :ok
  def period_usage(record_date) do
    Billing
    |> where([b], b.is_active == true)
    |> Repo.all(skip_organization_id: true)
    |> Enum.each(&update_period_usage(&1, record_date))
  end

  @spec update_period_usage(Billing.t(), DateTime.t()) :: :ok
  defp update_period_usage(billing, end_date) do
    start_date =
      if is_nil(billing.stripe_last_usage_recorded),
        # if we dont have last_usage, set it to start of the week as we update it on weekly basis
        do: Timex.beginning_of_week(end_date),
        # We know the last time recorded usage, we bump the date
        # to the next day for this period
        else: billing.stripe_last_usage_recorded

    record_usage(billing.organization_id, start_date, end_date)
  end

  @doc """
  Record the usage for a specific organization from start_date to end_date
  both dates inclusive
  """
  @spec record_usage(non_neg_integer(), DateTime.t(), DateTime.t()) :: :ok
  def record_usage(organization_id, start_date, end_date) do
    # putting organization id in process for fetching stat data
    Repo.put_process_state(organization_id)

    billing = Repo.get_by!(Billing, %{organization_id: organization_id, is_active: true})
    subscription_items = billing.stripe_subscription_items

    # formatting dates
    dates = format_dates(start_date, end_date)

    organization_id
    |> update_message_usage(dates, subscription_items)
    |> update_consulting_hour(start_date, end_date, dates, subscription_items)

    if Timex.days_in_month(end_date) - end_date.day == 0,
      do: add_metered_users(organization_id, end_date, subscription_items)

    {:ok, _} = update_billing(billing, %{stripe_last_usage_recorded: dates.end_usage_datetime})
    :ok
  end

  @spec update_message_usage(non_neg_integer(), map(), map()) :: non_neg_integer
  defp update_message_usage(organization_id, dates, subscription_items) do
    case Stats.usage(organization_id, dates.start_usage_date, dates.end_usage_date) do
      nil ->
        organization_id

      usage ->
        record_subscription_item(
          subscription_items[stripe_ids()["messages"]],
          # dividing the messages as every 10 message is 1 unit in stripe messages subscription item
          div(usage.messages, 10),
          dates.time,
          "messages: #{organization_id}, #{Date.to_string(dates.start_usage_date)}"
        )
    end

    organization_id
  end

  @spec update_consulting_hour(non_neg_integer(), DateTime.t(), DateTime.t(), map(), map()) ::
          true | {:error, Stripe.Error.t()} | {:ok, Stripe.SubscriptionItem.Usage.t()}
  defp update_consulting_hour(organization_id, start_date, end_date, dates, subscription_items) do
    with consulting_hours <-
           calculate_consulting_hours(organization_id, start_date, end_date).duration,
         false <- is_nil(consulting_hours) do
      record_subscription_item(
        subscription_items[stripe_ids()["consulting_hours"]],
        # dividing the consulting hours as every 15 min is 1 unit in stripe consulting hour subscription item
        div(consulting_hours, 15),
        dates.time,
        "consulting: #{organization_id}, #{Date.to_string(dates.start_usage_date)}"
      )
    end
  end

  @spec add_metered_users(non_neg_integer(), DateTime.t(), map()) :: :ok
  defp add_metered_users(organization_id, end_date, subscription_items) do
    start_date = end_date |> Timex.beginning_of_month() |> Timex.beginning_of_day()
    dates = format_dates(start_date, end_date)

    Logger.info(
      "Updating metered user in billing for org_id: #{organization_id} between #{dates.start_usage_date} and #{dates.end_usage_date}"
    )

    case Stats.usage(organization_id, dates.start_usage_date, dates.end_usage_date) do
      %{messages: _messages, users: users} ->
        record_subscription_item(
          subscription_items[stripe_ids()["users"]],
          users,
          dates.time,
          "users: #{organization_id}, #{Date.to_string(dates.start_usage_date)}"
        )

      nil ->
        :ok
    end
  end

  # record the usage against a subscription item in stripe
  @spec record_subscription_item(String.t(), pos_integer, pos_integer, String.t()) ::
          {:ok, Usage.t()} | {:error, Stripe.Error.t()}
  defp record_subscription_item(subscription_item_id, quantity, time, idempotency) do
    Usage.create(
      subscription_item_id,
      %{
        quantity: quantity,
        timestamp: time
      },
      idempotency_key: idempotency
    )
  end

  @spec calculate_consulting_hours(non_neg_integer(), DateTime.t(), DateTime.t()) :: map()
  defp calculate_consulting_hours(organization_id, start_date, end_date) do
    ConsultingHour
    |> where([ch], ch.organization_id == ^organization_id)
    |> where([ch], ch.is_billable == true)
    |> where([ch], ch.inserted_at >= ^start_date)
    |> where([ch], ch.inserted_at <= ^end_date)
    |> select([f], %{duration: sum(f.duration)})
    |> Repo.one(skip_organization_id: true)
  end

  @doc """
  fetches customer portal url of organization with billing status as active
  """
  @spec customer_portal_link(Billing.t()) :: {:ok, any()} | {:error, String.t()}
  def customer_portal_link(billing) do
    organization = Partners.organization(billing.organization_id)

    params = %{
      customer: billing.stripe_customer_id,
      return_url: "https://#{organization.shortcode}.tides.coloredcow.com/settings/billing"
    }

    BillingPortal.Session.create(params)
    |> case do
      {:ok, response} ->
        {:ok, %{url: response.url, return_url: response.return_url}}

      _ ->
        {:error, "Invalid Stripe Key"}
    end
  end

  # events that we need to handle, delete comment once handled :)
  # invoice.upcoming
  # invoice.created - send final usage record here, also send on a weekly basis, to avoid error
  # invoice.paid
  # invoice.payment_failed
  # invoice.payment_action_required
end
