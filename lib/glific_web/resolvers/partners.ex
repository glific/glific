defmodule GlificWeb.Resolvers.Partners do
  @moduledoc """
  Partners Resolver which sits between the GraphQL schema and Glific Partners Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    Partners,
    Partners.Credential,
    Partners.Organization,
    Partners.Provider,
    Repo
  }

  @doc """
  Get a specific organization by id
  """
  @spec organization(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def organization(_, %{id: id}, _) do
    with {:ok, organization} <- Repo.fetch(Organization, id, skip_organization_id: true),
         do: {:ok, %{organization: organization}}
  end

  def organization(_, _, %{context: %{current_user: current_user}}) do
    with {:ok, organization} <-
           Repo.fetch(Organization, current_user.organization_id, skip_organization_id: true),
         do: {:ok, %{organization: organization}}
  end

  @doc """
  Get the list of organizations filtered by args
  """
  @spec organizations(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def organizations(_, args, _) do
    {:ok, Partners.list_organizations(args)}
  end

  @doc """
  Get the count of organizations filtered by args
  """
  @spec count_organizations(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_organizations(_, args, _) do
    {:ok, Partners.count_organizations(args)}
  end

  @doc """
  Creates an organization
  """
  @spec create_organization(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_organization(_, %{input: params}, _) do
    with {:ok, organization} <- Partners.create_organization(params) do
      {:ok, %{organization: organization}}
    end
  end

  @doc """
  Updates an organization
  """
  @spec update_organization(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) :: {:ok, any} | {:error, any}
  def update_organization(_, %{id: id, input: params}, _) do
    with {:ok, organization} <- Repo.fetch(Organization, id, skip_organization_id: true),
         {:ok, organization} <- Partners.update_organization(organization, params) do
      {:ok, %{organization: organization}}
    end
  end

  @doc """
  Deletes an organization
  """
  @spec delete_organization(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_organization(_, %{id: id}, _) do
    with {:ok, organization} <- Repo.fetch(Organization, id),
         {:ok, organization} <- Partners.delete_organization(organization) do
      {:ok, organization}
    end
  end

  @doc """
  Get a specific provider by id
  """
  @spec provider(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def provider(_, %{id: id}, _) do
    with {:ok, provider} <- Repo.fetch(Provider, id),
         do: {:ok, %{provider: provider}}
  end

  @doc """
  Get the list of providers
  """
  @spec providers(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, any} | {:error, any}
  def providers(_, args, _) do
    {:ok, Partners.list_providers(args)}
  end

  @doc """
  Get the count of providers filtered by args
  """
  @spec count_providers(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_providers(_, args, _) do
    {:ok, Partners.count_providers(args)}
  end

  @doc """
  Get a specific bsp balance by organization id
  """
  @spec bspbalance(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def bspbalance(_, _, %{context: %{current_user: user}}) do
    with {:ok, balance} <- Partners.get_bsp_balance(user.organization_id)
         do
        IO.inspect(balance)
          {:ok, %{bsp_balance_result: balance}}
        end
  end

  @doc """
  Creates a provider
  """
  @spec create_provider(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_provider(_, %{input: params}, _) do
    with {:ok, provider} <- Partners.create_provider(params) do
      {:ok, %{provider: provider}}
    end
  end

  @doc """
  Updates a provider
  """
  @spec update_provider(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def update_provider(_, %{id: id, input: params}, _) do
    with {:ok, provider} <- Repo.fetch(Provider, id),
         {:ok, provider} <- Partners.update_provider(provider, params) do
      {:ok, %{provider: provider}}
    end
  end

  @doc """
  Deletes a provider
  """
  @spec delete_provider(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_provider(_, %{id: id}, _) do
    with {:ok, provider} <- Repo.fetch(Provider, id),
         {:ok, provider} <- Partners.delete_provider(provider) do
      {:ok, provider}
    end
  end

  @doc """
  Get organization's credential by shorcode/service
  """
  @spec credential(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def credential(_, %{shortcode: shortcode}, %{
        context: %{current_user: current_user}
      }) do
    with {:ok, credential} <-
           Partners.get_credential(%{
             organization_id: current_user.organization_id,
             shortcode: shortcode
           }),
         do: {:ok, %{credential: credential}}
  end

  @doc """
  Creates an organization's credential
  """
  @spec create_credential(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def create_credential(_, %{input: params}, %{
        context: %{current_user: current_user}
      }) do
    with {:ok, credential} <-
           Partners.create_credential(
             Map.merge(params, %{organization_id: current_user.organization_id})
           ) do
      {:ok, %{credential: credential}}
    end
  end

  @doc """
  Updates an organization's credential
  """
  @spec update_credential(Absinthe.Resolution.t(), %{id: integer, input: map()}, %{
          context: map()
        }) ::
          {:ok, any} | {:error, any}
  def update_credential(_, %{id: id, input: params}, %{
        context: %{current_user: current_user}
      }) do
    with {:ok, credential} <-
           Repo.fetch_by(Credential, %{
             id: id,
             organization_id: current_user.organization_id
           }),
         {:ok, credential} <-
           Partners.update_credential(credential, params) do
      {:ok, %{credential: credential}}
    end
  end
end
