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
          {:ok, any} | {:error, any}
  def create_subscription(_, %{input: params}, _) do
    with organization <- Partners.organization(params.organization_id),
         {:ok, subscription} <-
           Billing.create_subscription(organization, params.stripe_payment_method_id) do
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
