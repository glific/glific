defmodule GlificWeb.Schema do
  @moduledoc """
  This is the container for the top level Absinthe GraphQL schema which encapsulates the entire Glific Public API.
  This file is primarily a container and pulls in the relevant information for data type specific files.
  """

  use Absinthe.Schema

  alias Glific.Repo
  alias GlificWeb.Schema.Middleware

  import_types(Absinthe.Type.Custom)

  import_types(__MODULE__.ContactTypes)
  import_types(__MODULE__.BalanceTypes)
  import_types(__MODULE__.ContactTagTypes)
  import_types(__MODULE__.EnumTypes)
  import_types(__MODULE__.GenericTypes)
  import_types(__MODULE__.LanguageTypes)
  import_types(__MODULE__.MessageTypes)
  import_types(__MODULE__.MessageMediaTypes)
  import_types(__MODULE__.MessageTagTypes)
  import_types(__MODULE__.OrganizationTypes)
  import_types(__MODULE__.CredentialTypes)
  import_types(__MODULE__.ProviderTypes)
  import_types(__MODULE__.SessionTemplateTypes)
  import_types(__MODULE__.TemplateTagTypes)
  import_types(__MODULE__.TagTypes)
  import_types(__MODULE__.UserTypes)
  import_types(__MODULE__.GroupTypes)
  import_types(__MODULE__.ContactGroupTypes)
  import_types(__MODULE__.UserGroupTypes)
  import_types(__MODULE__.SearchTypes)
  import_types(__MODULE__.FlowTypes)

  query do
    import_fields(:contact_queries)

    import_fields(:language_queries)

    import_fields(:message_queries)

    import_fields(:message_media_queries)

    import_fields(:organization_queries)

    import_fields(:credential_queries)

    import_fields(:provider_queries)

    import_fields(:session_template_queries)

    import_fields(:tag_queries)

    import_fields(:user_queries)

    import_fields(:group_queries)

    import_fields(:search_queries)

    import_fields(:flow_queries)
  end

  mutation do
    import_fields(:contact_mutations)

    import_fields(:contact_tag_mutations)

    import_fields(:language_mutations)

    import_fields(:message_mutations)

    import_fields(:message_media_mutations)

    import_fields(:message_tag_mutations)

    import_fields(:organization_mutations)

    import_fields(:credential_mutations)

    import_fields(:provider_mutations)

    import_fields(:session_template_mutations)

    import_fields(:template_tag_mutations)

    import_fields(:tag_mutations)

    import_fields(:user_mutations)

    import_fields(:group_mutations)

    import_fields(:contact_group_mutations)

    import_fields(:user_group_mutations)

    import_fields(:search_mutations)

    import_fields(:flow_mutations)
  end

  subscription do
    import_fields(:message_subscriptions)

    import_fields(:message_tag_subscriptions)

    import_fields(:gupshup_balance)
  end

  @doc """
  Used to apply middleware on all or a group of fields based on pattern matching.

  It is passed the existing middleware for a field, the field itself, and the object that the field is a part of.
  """

  @spec middleware(
          [Absinthe.Middleware.spec(), ...],
          Absinthe.Type.Field.t(),
          Absinthe.Type.Object.t()
        ) :: [Absinthe.Middleware.spec(), ...]
  def middleware(middleware, _field, %{identifier: :mutation}),
    do: [Middleware.AddOrganization | middleware] ++ [Middleware.ChangesetErrors]

  def middleware(middleware, _field, %{identifier: :query}),
    do: [Middleware.AddOrganization | middleware] ++ [Middleware.QueryErrors]

  def middleware(middleware, _field, _object),
    do: middleware

  @doc """
  Used to set some values in the context that we may need in order to run. For now we are just using it
  for Dataloader perspectives.

  I think we will be storing authentication and current user in the context map in future releases. We have
  already started storing current user info in the context map.
  """
  @spec context(map()) :: map()
  def context(ctx) do
    loader =
      Dataloader.new()
      |> Dataloader.add_source(
        Repo,
        Dataloader.Ecto.new(Repo, repo_opts: [organization_id: ctx.current_user.organization_id])
      )

    Map.put(ctx, :loader, loader)
  end

  @doc """
  Used to define the list of plugins to run before and after resolution.
  """
  @spec plugins() :: [Absinthe.Plugin.t()]
  def plugins do
    [Absinthe.Middleware.Dataloader | Absinthe.Plugin.defaults()]
  end

  @doc """
  Validation function for all subscriptions received by the system
  """
  @spec config_fun(map(), map()) :: {:ok, Keyword.t()} | {:error, String.t()}
  def config_fun(args, %{context: %{current_user: user}}) do
    organization_id = args.organization_id

    if organization_id == Integer.to_string(user.organization_id) do
      {:ok, [topic: organization_id, context_id: organization_id]}
    else
      {:error, "Credentials did not match"}
    end
  end
end
