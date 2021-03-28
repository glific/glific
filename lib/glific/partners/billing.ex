defmodule Glific.Partners.Billing do
  @moduledoc """
  We will use this as the main context interface for all billing subscriptions and the stripe
  interface.
  """

  alias Glific.{Partners, Partners.Organization}

  @doc """
  Create a billing customer in Stripe, given an organization
  """
  @spec create(Organization.t()) :: {:ok, Organization.t()} | {:error, String.t()}
  def create(organization) do
    case check_required(organization) do
      {:error, error} -> {:error, error}
      _ -> do_create(organization)
    end
  end

  @spec do_create(Organization.t()) :: {:ok, Organization.t()} | {:error, String.t()}
  defp do_create(organization) do
    {:ok, stripe_customer} =
      %{
        name: organization.billing_name,
        email: organization.billing_email,
        # currency: organization.billing_currency,
        metadata: %{
          "id" => Integer.to_string(organization.id),
          "name" => organization.name
        }
      }
      |> Stripe.Customer.create()

    Partners.update_organization(
      organization,
      %{stripe_customer_id: stripe_customer.id}
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
  @spec check_required(Organization.t()) :: :ok | {:error, String.t()}
  defp check_required(organization) do
    [:billing_name, :billing_email, :billing_currency]
    |> Enum.reduce(
      [],
      fn field, acc ->
        value = Map.get(organization, field)

        if is_nil(value) || value == "" do
          ["#{field} is not set" | acc]
        end
      end
    )
    |> check_stripe_key()
    |> format_errors()
  end

  @spec stripe_ids(atom()) :: map()
  defp stripe_ids(:prod) do
    %{}
  end

  defp stripe_ids(_env) do
    %{
      product: "prod_JBiFSE44OOhpgO",
      setup: "price_0IZKpSZVZ2O8W9YsDAlqiu5P",
      monthly: "price_0IZKpSZVZ2O8W9Ys0tU8WArK",
      users: "price_0IZLSKZVZ2O8W9YsB9arj9uR",
      messages: "price_0IZLWnZVZ2O8W9YsF6GiMmGX",
      hours: "price_0IZLfSZVZ2O8W9Ysy3SjpmPJ"
    }
  end

  @spec subscription_params(Organization.t(), String.t()) :: map()
  defp subscription_params(organization, stripe_payment_method_id) do
    prices = stripe_ids(Application.get_env(:glific, :environment))

    %{
      customer: organization.stripe_customer_id,
      default_payment_method: stripe_payment_method_id,
      items: [
        %{
          price: prices.setup,
          quantity: 1
        },
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
          price: prices.hours
        }
      ],
      metadata: %{
        "id" => Integer.to_string(organization.id),
        "name" => organization.name
      }
    }
  end

  @doc """
  Once the organization has entered a new payment card we create a subscription for it.
  We'll do updating the card in a seperate function
  """
  @spec create_subscription(Organization.t(), String.t()) ::
          {:ok, Organization.t()} | {:error, String.t()}
  def create_subscription(organization, stripe_payment_method_id) do
    # first update the contact with default payment id
    {:ok, _customer} =
      Stripe.Customer.update(
        organization.stripe_customer_id,
        %{
          invoice_settings: %{
            default_payment_method: stripe_payment_method_id
          }
        }
      )

    # now create and attach the subscriptions to this organization
    params = subscription_params(organization, stripe_payment_method_id)

    case Stripe.Subscription.create(params) do
      {:ok, subscription} ->
        Partners.update_organization(
          organization,
          %{
            stripe_payment_method_id: stripe_payment_method_id,
            strip_subscription_id: subscription.id
          }
        )

      {:error, stripe_error} ->
        {:error, inspect(stripe_error)}
    end
  end
end
