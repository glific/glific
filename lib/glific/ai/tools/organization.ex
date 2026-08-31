defmodule Glific.AI.Tools.Organization do
  @moduledoc """
  Reads about the organisation itself: who it is, what it has switched on, which
  providers are wired up, what the platform is warning about, and how much
  traffic it is carrying.

  Credential *values* are never returned — only whether a provider is configured,
  active and valid, which is what a question about a service failing needs.
  """

  import Ecto.Query

  alias Glific.{
    Certificates.CertificateTemplate,
    Jobs,
    Notifications,
    Partners,
    Partners.Credential,
    Repo,
    Searches,
    Settings,
    Stats,
    Users
  }

  @behaviour Glific.AI.Tool

  @impl Glific.AI.Tool
  def specs do
    [
      %{
        name: "organization_info",
        description: """
        Describes this organisation: its name, timezone and which services are
        switched on. Use this to check whether a feature the question depends on
        is enabled at all.
        """,
        parameters: []
      },
      %{
        name: "provider_status",
        description: """
        Lists the third-party providers configured for this organisation — the
        WhatsApp BSP, storage, analytics and so on — and whether each is active
        and its credentials still valid. Start here when a whole service has
        stopped working rather than one flow. Credential values are never shown.
        """,
        parameters: []
      },
      %{
        name: "list_notifications",
        description: """
        Lists the platform's own warnings and errors for this organisation,
        newest first. Use this when something is failing and the cause is not in
        a flow — a credential problem or a provider outage shows up here.
        """,
        parameters: [
          severity: [type: :string, doc: ~s(Only this severity, e.g. "Critical" or "Warning")],
          category: [type: :string, doc: ~s(Only this category, e.g. "Message" or "Flow")],
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      },
      %{
        name: "daily_stats",
        description: """
        Returns this organisation's daily counts: messages in and out, active
        contacts, opt-ins and opt-outs, flows started and completed. Use this
        for questions about volume or trend over time.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 30, doc: "How many days to return, at most 90"]
        ]
      },
      %{
        name: "list_users",
        description: """
        Lists the staff accounts in this organisation with their roles. Use this
        to answer who has access, or to attribute an action to a person.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 50, doc: "How many to return, at most 200"]
        ]
      },
      %{
        name: "list_languages",
        description: """
        Lists the languages available on the platform. Templates and contacts
        carry a language_id, and this is what turns that id into a name.
        """,
        parameters: []
      },
      %{
        name: "organization_data",
        description: """
        Lists this organisation's global fields — the shared values flows read
        by key. A flow substituting an empty global is usually a key that does
        not exist here.
        """,
        parameters: [
          limit: [type: :pos_integer, default: 50, doc: "How many to return, at most 200"]
        ]
      },
      %{
        name: "sync_jobs",
        description: """
        Reports how far this organisation's BigQuery export has got, per table.
        A table whose last update is stale is a sync that has stopped.
        """,
        parameters: []
      },
      %{
        name: "list_saved_searches",
        description: "Lists the saved searches staff use in the chat inbox.",
        parameters: [
          limit: [type: :pos_integer, default: 50, doc: "How many to return, at most 200"]
        ]
      },
      %{
        name: "list_certificate_templates",
        description: "Lists the certificate templates this organisation can issue from flows.",
        parameters: [
          limit: [type: :pos_integer, default: 25, doc: "How many to return, at most 100"]
        ]
      }
    ]
  end

  @impl Glific.AI.Tool
  def run("organization_info", _args) do
    organization = Partners.organization(Repo.get_organization_id())

    {:ok,
     %{
       id: organization.id,
       name: organization.name,
       shortcode: organization.shortcode,
       timezone: organization.timezone,
       status: organization.status,
       is_active: organization.is_active,
       services: organization.services |> Map.keys() |> Enum.sort()
     }}
  end

  # Only the shape of each credential, never `keys` or `secrets`: those hold the
  # provider's API tokens and must not reach a model.
  def run("provider_status", _args) do
    providers =
      Credential
      |> preload(:provider)
      |> Repo.all()
      |> Enum.map(
        &%{
          provider: &1.provider.name,
          shortcode: &1.provider.shortcode,
          group: &1.provider.group,
          is_active: &1.is_active,
          is_valid: &1.is_valid
        }
      )

    {:ok, providers}
  end

  def run("list_notifications", args) do
    filter =
      %{}
      |> maybe_put(:severity, args[:severity])
      |> maybe_put(:category, args[:category])

    notifications =
      %{filter: filter, opts: %{limit: min(args[:limit], 100), offset: 0, order: :desc}}
      |> Notifications.list_notifications()
      |> Enum.map(
        &%{
          category: &1.category,
          severity: &1.severity,
          message: &1.message,
          is_read: &1.is_read,
          inserted_at: &1.inserted_at
        }
      )

    {:ok, notifications}
  end

  def run("daily_stats", args) do
    stats =
      %{filter: %{period: "day"}, opts: %{limit: min(args[:limit], 90), offset: 0, order: :desc}}
      |> Stats.list_stats()
      |> Enum.map(
        &%{
          date: &1.date,
          contacts: &1.contacts,
          active: &1.active,
          optin: &1.optin,
          optout: &1.optout,
          inbound: &1.inbound,
          outbound: &1.outbound,
          hsm: &1.hsm,
          flows_started: &1.flows_started,
          flows_completed: &1.flows_completed,
          conversations: &1.conversations
        }
      )

    {:ok, stats}
  end

  def run("list_users", args) do
    users =
      %{filter: %{}, opts: %{limit: min(args[:limit], 200), offset: 0, order: :asc}}
      |> Users.list_users()
      |> Enum.map(
        &%{
          id: &1.id,
          name: &1.name,
          roles: &1.roles,
          is_restricted: &1.is_restricted,
          last_login_at: &1.last_login_at
        }
      )

    {:ok, users}
  end

  def run("list_languages", _args) do
    languages =
      Settings.list_languages()
      |> Enum.map(&%{id: &1.id, label: &1.label, locale: &1.locale, is_active: &1.is_active})

    {:ok, languages}
  end

  def run("organization_data", args) do
    # No `order`: this context orders by a `name` column the table lacks.
    data =
      %{filter: %{}, opts: %{limit: min(args[:limit], 200), offset: 0}}
      |> Partners.list_organization_data()
      |> Enum.map(&%{key: &1.key, description: &1.description, text: &1.text, json: &1.json})

    {:ok, data}
  end

  def run("sync_jobs", _args) do
    jobs =
      Repo.get_organization_id()
      |> Jobs.get_bigquery_jobs()
      |> Enum.map(&%{table: &1.table, last_updated_at: &1.last_updated_at})

    {:ok, %{bigquery: jobs}}
  end

  def run("list_saved_searches", args) do
    searches =
      %{filter: %{}, opts: %{limit: min(args[:limit], 200), offset: 0, order: :asc}}
      |> Searches.list_saved_searches()
      |> Enum.map(
        &%{id: &1.id, label: &1.label, shortcode: &1.shortcode, is_reserved: &1.is_reserved}
      )

    {:ok, searches}
  end

  def run("list_certificate_templates", args) do
    templates =
      %{filter: %{}, opts: %{limit: min(args[:limit], 100), offset: 0, order: :asc}}
      |> CertificateTemplate.list_certificate_templates()
      |> Enum.map(&%{id: &1.id, label: &1.label, description: &1.description, url: &1.url})

    {:ok, templates}
  end

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(filter, _key, nil), do: filter
  defp maybe_put(filter, key, value), do: Map.put(filter, key, value)
end
