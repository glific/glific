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
end
