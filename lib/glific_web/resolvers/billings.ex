defmodule GlificWeb.Resolvers.Billings do
  @moduledoc """
  Billing Resolver which sits between the GraphQL schema and Glific Billing Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{Partners, Partners.Billing, Repo}
  alias GlificWeb.Schema.Middleware.Authorize

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
  def get_organization_billing(_, input, %{context: %{current_user: user}}) do
    ## here we are assuming that there will be a single active billing entry for the organization.
    org_id = target_org_id(user, input[:organization_id])

    with {:ok, billing} <-
           Repo.fetch_by(Billing, %{is_active: true, organization_id: org_id},
             skip_organization_id: true
           ),
         do: {:ok, %{billing: billing}}
  end

  @doc false
  @spec get_promo_code(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def get_promo_code(_, %{code: code}, _),
    do: Billing.get_promo_codes(code)

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
  def create_billing(_, %{input: params}, %{context: %{current_user: user}}) do
    org_id = target_org_id(user, params[:organization_id])
    params = Map.put(params, :organization_id, org_id)

    with organization <- Partners.organization(org_id),
         {:ok, billing} <- Billing.create(organization, params) do
      {:ok, %{billing: billing}}
    end
  end

  @doc false
  @spec update_billing(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_billing(_, %{id: id, input: params}, %{context: %{current_user: user}}) do
    # An update must never re-home a billing to another org; the target org is fixed by the
    # record we fetch. So drop any organization_id (client-supplied, or auto-injected by the
    # AddOrganization middleware) from the update params for every role.
    params = Map.delete(params, :organization_id)

    # glific_admin keeps cross-org fetch ability; every other role is pinned to its own org.
    {fetch_clauses, fetch_opts} =
      if Authorize.valid_role?(user.roles, :glific_admin),
        do: {%{id: id}, [skip_organization_id: true]},
        else: {%{id: id, organization_id: user.organization_id}, []}

    with {:ok, billing} <- Repo.fetch_by(Billing, fetch_clauses, fetch_opts),
         {:ok, billing} <- Billing.update_stripe_customer(billing, params),
         {:ok, billing} <- Billing.update_billing(billing, params) do
      {:ok, %{billing: billing}}
    end
  end

  @doc false
  @spec update_payment_method(Absinthe.Resolution.t(), map(), %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_payment_method(_, params, _) do
    with organization <- Partners.organization(params.organization_id),
         {:ok, billing} <-
           Billing.update_payment_method(organization, params.stripe_payment_method_id) do
      {:ok, %{billing: billing}}
    end
  end

  @doc false
  @spec create_subscription(Absinthe.Resolution.t(), map(), %{
          context: map()
        }) ::
          {:ok | :error | :pending, any}
  def create_subscription(_, params, _) do
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
           Repo.fetch_by(Billing, %{id: id, organization_id: user.organization_id}) do
      Billing.delete_billing(billing)
    end
  end

  # glific_admin may target a client-supplied org (SaaS operator managing another org's
  # billing); every other role is pinned to its own org regardless of what is supplied.
  @spec target_org_id(Glific.Users.User.t(), integer() | nil) :: integer()
  defp target_org_id(user, client_org_id) do
    if Authorize.valid_role?(user.roles, :glific_admin),
      do: client_org_id || user.organization_id,
      else: user.organization_id
  end
end
