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
    :is_active
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
    prices = stripe_ids()

    # Temporary to make sure that the subscription starts from the beginning of next month
    anchor_timestamp =
      DateTime.utc_now()
      |> Timex.end_of_month()
      |> Timex.shift(days: 1)
      |> Timex.beginning_of_day()
      |> DateTime.to_unix()

    %{
      customer: billing.stripe_customer_id,
      # Temporary for existing customers.
      billing_cycle_anchor: anchor_timestamp,
      prorate: false,
      items: [
        %{
          price: prices["monthly"],
          quantity: 1
        },
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
  defp apply_coupon(invoice_id, %{coupon_code: coupon_code}) do
    make_stripe_request("invoiceitems/#{invoice_id}", :post, %{
      discounts: [%{coupon: coupon_code}]
    })
  end

  defp apply_coupon(_, _), do: nil

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
    # now create and attach the subscriptions to this organization
    params = subscription_params(billing, organization)
    opts = [expand: ["latest_invoice.payment_intent", "pending_setup_intent"]]

    make_stripe_request("subscriptions", :post, params, opts)
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
      Stripe.SubscriptionItem.delete(subscription_item, %{clear_usage: false}, [])
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

    Stripe.SubscriptionItem.delete(
      billing.stripe_subscription_items[stripe_ids()["monthly"]],
      %{},
      []
    )

    Stripe.Subscription.update(billing.stripe_subscription_id, params, [])
    organization
  end

  def update_subscription(billing, %{status: status} = organization) when status in [:inactive, :ready_to_delete] do
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
      stripe_current_period_end: period_end,
      stripe_last_usage_recorded: nil
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
  defp subscription_requires_auth?(subscription),
    do:
      !is_nil(subscription.pending_setup_intent) &&
        subscription.pending_setup_intent.status == "requires_action"

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
          "Error while updating the subscription details for subscription #{subscription.id} and organization_id: #{
            organization_id
          }"
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

  # get dates and times in the right format for other functions
  @spec format_dates(DateTime.t(), DateTime.t()) ::
          {Date.t(), Date.t(), DateTime.t(), non_neg_integer}
  defp format_dates(start_date, end_date) do
    end_date = end_date |> Timex.end_of_day()

    {
      start_date |> DateTime.to_date(),
      end_date |> DateTime.to_date(),
      end_date,
      end_date |> DateTime.to_unix()
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

  # daily usage and weekly usage are the same
  @spec period_usage(DateTime.t()) :: :ok
  defp period_usage(end_date) do
    Billing
    |> where([b], b.is_active == true)
    |> Repo.all()
    |> Enum.each(&update_period_usage(&1, end_date))
  end

  @spec update_period_usage(Billing.t(), DateTime.t()) :: :ok
  defp update_period_usage(billing, end_date) do
    start_date =
      if is_nil(billing.stripe_last_usage_recorded),
        # if we dont have last_usage, set it from the subscription period date
        do: Timex.beginning_of_month(end_date),
        # We know the last time recorded usage, we bump the date
        # to the next day for this period
        else: billing.stripe_last_usage_recorded

    record_usage(billing.organization_id, start_date, end_date)
  end

  @doc """
  Record the usage for a specific organization from start_date to end_date
  both dates inclusive
  """
  @spec record_usage(non_neg_integer, DateTime.t(), DateTime.t()) :: :ok
  def record_usage(organization_id, start_date, end_date) do
    # formatting dates
    {start_usage_date, end_usage_date, end_usage_datetime, time} =
      format_dates(start_date, end_date)

    case Stats.usage(organization_id, start_usage_date, end_usage_date) do
      nil ->
        :ok

      usage ->
        billing = Repo.get_by!(Billing, %{organization_id: organization_id, is_active: true})
        prices = stripe_ids()
        subscription_items = billing.stripe_subscription_items

        record_subscription_item(
          subscription_items[prices["messages"]],
          # dividing the messages as every 10 message is 1 unit in stripe messages subscription item
          div(usage.messages, 10),
          time,
          "messages: #{organization_id}, #{Date.to_string(start_usage_date)}"
        )

        with consulting_hours <-
               calculate_consulting_hours(billing.organization_id, start_date, end_date).duration,
             false <- is_nil(consulting_hours) do
          record_subscription_item(
            subscription_items[prices["consulting_hours"]],
            # dividing the consulting hours as every 15 min is 1 unit in stripe consulting hour subscription item
            div(consulting_hours, 15),
            time,
            "consulting: #{billing.organization_id}, #{Date.to_string(start_usage_date)}"
          )
        end

        if Timex.days_in_month(end_date) - end_date.day == 0,
          do: add_metered_users(organization_id, end_date, prices, subscription_items)

        {:ok, _} = update_billing(billing, %{stripe_last_usage_recorded: end_usage_datetime})
    end

    :ok
  end

  defp add_metered_users(organization_id, end_date, prices, subscription_items) do
    start_date = end_date |> Timex.beginning_of_month() |> Timex.beginning_of_day()

    {start_usage_date, end_usage_date, _end_usage_datetime, time} =
      format_dates(start_date, end_date)

    case Stats.usage(organization_id, start_usage_date, end_usage_date) do
      usage ->
        record_subscription_item(
          subscription_items[prices["users"]],
          usage.users,
          time,
          "users: #{organization_id}, #{Date.to_string(start_usage_date)}"
        )
    end

    :ok
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
