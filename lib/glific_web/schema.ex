defmodule GlificWeb.Schema do
  @moduledoc """
  This is the container for the top level Absinthe GraphQL schema which encapsulates the entire Glific Public API.
  This file is primarily a container and pulls in the relevant information for data type specific files.
  """

  use Absinthe.Schema
  use Gettext, backend: GlificWeb.Gettext

  alias Glific.Repo

  alias GlificWeb.Schema.{
    Middleware,
    Middleware.SafeResolution
  }

  import_types(Absinthe.Type.Custom)

  # Important: Needed to use the `:upload` type
  import_types(Absinthe.Plug.Types)

  import_types(__MODULE__.OrganizationTypes)
  import_types(__MODULE__.ProfileTypes)
  import_types(__MODULE__.ContactTypes)
  import_types(__MODULE__.ContactTagTypes)
  import_types(__MODULE__.EnumTypes)
  import_types(__MODULE__.GenericTypes)
  import_types(__MODULE__.LanguageTypes)
  import_types(__MODULE__.MessageTypes)
  import_types(__MODULE__.MessageMediaTypes)
  import_types(__MODULE__.MessageTagTypes)
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
  import_types(__MODULE__.TriggerTypes)
  import_types(__MODULE__.WebhookLogTypes)
  import_types(__MODULE__.NotificationTypes)
  import_types(__MODULE__.LocationTypes)
  import_types(__MODULE__.BillingTypes)
  import_types(__MODULE__.MediaTypes)
  import_types(__MODULE__.ConsultingHourTypes)
  import_types(__MODULE__.ContactsFieldTypes)
  import_types(__MODULE__.ExtensionTypes)
  import_types(__MODULE__.InteractiveTemplateTypes)
  import_types(__MODULE__.FlowLabelTypes)
  import_types(__MODULE__.RoleTypes)
  import_types(__MODULE__.SheetTypes)
  import_types(__MODULE__.TicketTypes)
  import_types(__MODULE__.ContactWaGroupTypes)
  import_types(__MODULE__.WAManagedPhoneTypes)
  import_types(__MODULE__.WAGroupsCollectionTypes)
  import_types(__MODULE__.WaGroupTypes)
  import_types(__MODULE__.FilesearchTypes)
  import_types(__MODULE__.WaPollTypes)
  import_types(__MODULE__.CertificateTypes)
  import_types(__MODULE__.WhatsappFormTypes)
  import_types(__MODULE__.WhatsappFormResponseTypes)
  import_types(__MODULE__.WhatsappFormsRevisionTypes)

  query do
    import_fields(:profile_queries)

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

    import_fields(:trigger_queries)

    import_fields(:webhook_log_queries)

    import_fields(:notification_queries)

    import_fields(:location_queries)

    import_fields(:billing_queries)

    import_fields(:consulting_hours_queries)

    import_fields(:contacts_field_queries)

    import_fields(:extensions_queries)

    import_fields(:interactive_template_queries)

    import_fields(:flow_label_queries)

    import_fields(:access_role_queries)

    import_fields(:contact_group_queries)

    import_fields(:contact_wa_group_queries)

    import_fields(:sheet_queries)

    import_fields(:ticket_queries)

    import_fields(:wa_managed_phone_queries)

    import_fields(:wa_search_queries)

    import_fields(:wa_group_queries)

    import_fields(:filesearch_queries)

    import_fields(:wa_poll_queries)

    import_fields(:certificate_queries)

    import_fields(:whatsapp_form_queries)

    import_fields(:whatsapp_form_revision_queries)
  end

  mutation do
    import_fields(:profile_mutations)

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

    import_fields(:trigger_mutations)

    import_fields(:billing_mutations)

    import_fields(:media_mutations)

    import_fields(:consulting_hours_mutations)

    import_fields(:notification_mutations)

    import_fields(:contacts_field_mutations)

    import_fields(:extensions_mutations)

    import_fields(:interactive_template_mutations)

    import_fields(:access_role_mutations)

    import_fields(:sheet_mutations)

    import_fields(:ticket_mutations)

    import_fields(:contact_wa_group_mutations)

    import_fields(:wa_groups_collection_mutations)

    import_fields(:filesearch_mutations)

    import_fields(:wa_poll_mutations)

    import_fields(:certificate_mutations)

    import_fields(:whatsapp_form_mutations)

    import_fields(:whatsapp_form_revision_mutations)
  end

  subscription do
    import_fields(:message_subscriptions)

    import_fields(:message_tag_subscriptions)

    import_fields(:organization_subscriptions)
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
  def middleware(middleware, _field, %{identifier: type}) when type in [:query, :mutation] do
    middleware = [Middleware.AddOrganization | SafeResolution.apply(middleware)]

    if type == :mutation,
      do: middleware ++ [Middleware.ChangesetErrors],
      else: middleware ++ [Middleware.QueryErrors]
  end

  def middleware(middleware, _field, _object),
    do: middleware

  @spec repo_opts(map()) :: Keyword.t()
  defp repo_opts(%{current_user: user}) when user != nil,
    do: [organization_id: user.organization_id]

  defp repo_opts(_params), do: []

  @doc """
  Used to set some values in the context that we may need in order to run.
  We store the organization id and the current user in the context once the user has been
  authenticated
  """
  @spec context(map()) :: map()
  def context(ctx) do
    loader =
      Dataloader.new()
      |> Dataloader.add_source(
        Repo,
        Dataloader.Ecto.new(Repo, repo_opts: repo_opts(ctx))
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
      {:ok, [topic: organization_id]}
    else
      {:error, dgettext("errors", "Auth Credentials mismatch")}
    end
  end
end
