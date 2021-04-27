defmodule GlificWeb.Resolvers.Billings do
  @moduledoc """
  Billing Resolver which sits between the GraphQL schema and Glific Billing Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Partners, Partners.Billing, Repo}

  @doc """
  Get a specific billing by id
  """
  @spec billing(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def billing(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, billing} <-
           Repo.fetch_by(Billing, %{id: id, organization_id: user.organization_id}),
         do: {:ok, %{billing: billing}}
  end

  @doc false
  @spec get_organization_billing(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def get_organization_billing(_, _, %{context: %{current_user: user}}) do
    ## here we are assuming that there will be a single active billing entry for the organization.
    with {:ok, billing} <-
           Repo.fetch_by(Billing, %{is_active: true, organization_id: user.organization_id}),
         do: {:ok, %{billing: billing}}
  end

  @doc false
  @spec get_promo_code(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def get_promo_code(_, %{code: code}, _) do
    with promo_code <-
      Billing.get_promo_codes(code),
         do: {:ok, promo_code}
  end

  @doc false
  @spec customer_portal(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def customer_portal(_, _, %{context: %{current_user: user}}) do
    with {:ok, billing} <-
           Repo.fetch_by(Billing, %{is_active: true, organization_id: user.organization_id}),
         do: Billing.customer_portal_link(billing)
  end

  @doc false
  @spec create_billing(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_billing(_, %{input: params}, _) do
    with organization <- Partners.organization(params.organization_id),
         {:ok, billing} <- Billing.create(organization, params) do
      {:ok, %{billing: billing}}
    end
  end

  @doc false
  @spec update_billing(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_billing(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    with {:ok, billing} <-
           Repo.fetch_by(Billing, %{id: id, organization_id: user.organization_id}),
         {:ok, billing} <- Billing.update_stripe_customer(billing, params),
         {:ok, billing} <- Billing.update_billing(billing, params) do
      {:ok, %{billing: billing}}
    end
  end

  @doc false
  @spec update_payment_method(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_payment_method(_, %{input: params}, _) do
    with organization <- Partners.organization(params.organization_id),
         {:ok, billing} <-
           Billing.update_payment_method(organization, params.stripe_payment_method_id) do
      {:ok, %{billing: billing}}
    end
  end

  @doc false
  @spec create_subscription(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok | :error | :pending, any}
  def create_subscription(_, %{input: params}, _) do
    organization = Partners.organization(params.organization_id)

    Billing.create_subscription(organization, params)
    |> case do
      {:error, error} ->
        {:error, error}

      ## this is for pending and ok responses.
      {_status, subscription} ->
        {:ok, %{subscription: subscription}}
    end
  end

  @doc false
  @spec delete_billing(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_billing(_, %{id: id}, %{context: %{current_user: user}}) do
    with {:ok, billing} <-
           Repo.fetch_by(Billing, %{id: id, organization_id: user.organization_id}),
         {:ok, billing} <- Billing.delete_billing(billing) do
      {:ok, billing}
    end
  end
end
