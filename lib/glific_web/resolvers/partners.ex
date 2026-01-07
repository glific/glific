defmodule GlificWeb.Resolvers.Partners do
  @moduledoc """
  Partners Resolver which sits between the GraphQL schema and Glific Partners Context API. This layer basically stitches together
  one or more calls to resolve the incoming queries.
  """
  use Gettext, backend: GlificWeb.Gettext

  alias Glific.{
    Erase,
    Partners,
    Partners.Credential,
    Partners.Export,
    Partners.Organization,
    Partners.Provider,
    Providers.Gupshup.PartnerAPI,
    Repo,
    Saas.Onboard
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
  Get the organizations services
  """
  @spec organization_services(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, map()}
  def organization_services(_, _, %{context: %{current_user: user}}) do
    services =
      user.organization_id
      |> Partners.get_org_services_by_id()
      |> Glific.atomize_keys()

    {:ok, services}
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
  Deletes an organization as a background job.
  This prevents UI timeouts when deleting organizations with large amounts of data.
  """
  @spec delete_organization(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_organization(_, %{id: id}, _) do
    with {:ok, organization} <- Repo.fetch(Organization, id, skip_organization_id: true) do
      Erase.delete_organization(id)
      {:ok, %{organization: organization}}
    end
  end

  @doc """
  Deletes all the test (dynamic) data of an organization
  """
  @spec delete_organization_test_data(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_organization_test_data(_, %{id: id}, _) do
    # make sure organization exists
    with {:ok, organization} <- Repo.fetch(Organization, id) do
      Partners.delete_organization_test_data(organization)
    end
  end

  @doc """
  Updates an organization status is_active/is_approved. We will add checks to
  validate approval and activation
  """

  @spec update_organization_status(Absinthe.Resolution.t(), map(), %{
          context: map()
        }) :: {:ok, any} | {:error, any}
  def update_organization_status(
        _,
        %{
          update_organization_id: update_organization_id,
          status: status
        },
        _
      ) do
    with organization <- Onboard.status(update_organization_id, status),
         do: {:ok, %{organization: organization}}
  end

  @doc """
  Delete an inactive organization
  """
  @spec delete_inactive_organization(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, any} | {:error, any}
  def delete_inactive_organization(
        _,
        %{
          delete_organization_id: delete_organization_id,
          is_confirmed: is_confirmed
        },
        _
      ) do
    with {:ok, organization} <- Onboard.delete(delete_organization_id, is_confirmed) do
      {:ok, %{organization: organization}}
    end
  end

  @doc """
  Resets table and some columns of an  organization
  """
  @spec reset_organization(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok | :error, String.t()}
  def reset_organization(
        _,
        %{
          reset_organization_id: reset_organization_id,
          is_confirmed: is_confirmed
        },
        _
      ) do
    Onboard.reset(reset_organization_id, is_confirmed)
  end

  @doc """
  Export dynamic data of an organization
  """
  @spec organization_export_data(
          Absinthe.Resolution.t(),
          %{filter: %{start_time: DateTime.t()}},
          %{context: map()}
        ) ::
          {:ok, %{data: map}} | {:error, any}
  def organization_export_data(_, %{filter: %{start_time: _start_time}} = args, %{
        context: %{current_user: user}
      }) do
    with {:ok, _organization} <- Repo.fetch(Organization, user.organization_id) do
      {:ok, %{data: Export.export_data(user.organization_id, args.filter)}}
    end
  end

  @doc """
  Export global stats of an organization
  """
  @spec organization_export_stats(Absinthe.Resolution.t(), map, %{context: map()}) ::
          {:ok, %{data: map}} | {:error, any}
  def organization_export_stats(_, args, %{context: %{current_user: user}}) do
    with {:ok, _organization} <- Repo.fetch(Organization, user.organization_id) do
      {:ok, %{data: Export.export_stats(user.organization_id, args.filter)}}
    end
  end

  @doc """
  Export config data of Glific (useful to all organizations)
  """
  @spec organization_export_config(Absinthe.Resolution.t(), map, %{context: map()}) ::
          {:ok, %{data: map}} | {:error, any}
  def organization_export_config(_, _, %{context: %{current_user: user}}) do
    with {:ok, _organization} <- Repo.fetch(Organization, user.organization_id) do
      {:ok, %{data: Export.export_config()}}
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
  Get the quality rating details of provider
  """
  @spec quality_rating(Absinthe.Resolution.t(), map(), %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def quality_rating(_, _, %{context: %{current_user: user}}) do
    Partners.get_quality_rating(user.organization_id)
    |> case do
      {:ok, data} -> {:ok, data}
      _ -> {:error, dgettext("errors", "Error while fetching Quality Rating details")}
    end
  end

  @doc """
  Get a specific bsp balance by organization id
  """
  @spec bspbalance(Absinthe.Resolution.t(), %{id: integer}, %{context: map()}) ::
          {:ok, any} | {:error, any}
  def bspbalance(_, _, %{context: %{current_user: user}}),
    do: get_balance(user.organization_id)

  @spec get_balance(non_neg_integer) :: {:ok, map()} | {:error, String.t()}
  defp get_balance(organization_id) do
    Partners.get_bsp_balance(organization_id)
    |> case do
      {:ok, data} -> {:ok, %{balance: data["balance"]}}
      _ -> {:error, dgettext("errors", "Error while fetching the BSP balance")}
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
    with {:ok, provider} <- Repo.fetch(Provider, id) do
      Partners.delete_provider(provider)
    end
  end

  @doc """
  Get organization's credential by shortcode/service
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
         {:ok, updated_credential} <-
           Partners.update_credential(credential, params) do
      {:ok, %{credential: updated_credential}}
    end
  end

  @doc """
  Gets daily app usage
  """
  @spec get_app_usage(Absinthe.Resolution.t(), %{from_date: Date.t(), to_date: Date.t()}, %{
          context: map()
        }) ::
          {:ok, list(map())} | {:error, String.t()}
  def get_app_usage(_parent, %{from_date: from_date, to_date: to_date}, %{
        context: %{current_user: user}
      }) do
    case PartnerAPI.get_app_usage(
           user.organization_id,
           Date.to_string(from_date),
           Date.to_string(to_date)
         ) do
      {:ok, response} ->
        {:ok,
         Enum.map(response, fn day ->
           %{
             date: Map.get(day, "date", ""),
             cumulative_bill: Map.get(day, "cumulativeBill", 0.0),
             discount: Map.get(day, "discount", 0.0),
             fep: Map.get(day, "fep", 0),
             ftc: Map.get(day, "ftc", 0),
             gupshup_cap: Map.get(day, "gsCap", 0.0),
             gupshup_fees: Map.get(day, "gsFees", 0.0),
             incoming_msg: Map.get(day, "incomingMsg", 0),
             outgoing_msg: Map.get(day, "outgoingMsg", 0),
             outgoing_media_msg: Map.get(day, "outgoingMediaMsg", 0),
             marketing: Map.get(day, "marketing", 0),
             service: Map.get(day, "service", 0),
             utility: Map.get(day, "utility", 0),
             template_msg: Map.get(day, "templateMsg", 0),
             template_media_msg: Map.get(day, "templateMediaMsg", 0),
             total_fees: Map.get(day, "totalFees", 0.0),
             whatsapp_fees: Map.get(day, "waFees", 0.0),
             total_msg: Map.get(day, "totalMsg", 0)
           }
         end)}

      {:error, _error} ->
        {:error, "Error fetching daily app usage list"}
    end
  end
end
