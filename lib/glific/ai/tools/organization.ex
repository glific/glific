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
    Jobs,
    Notifications,
    Partners,
    Partners.Credential,
    Repo,
    Stats,
    Users
  }

  @behaviour Glific.AI.Tool

  @doc "Every organisation-level lookup this module offers."
  @impl Glific.AI.Tool
  @spec specs() :: [Glific.AI.Tool.spec()]
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
        name: "platform_health",
        description: """
        Why the platform itself is unhealthy, when a whole service has stopped
        rather than one flow. Returns three things together, because the cause is
        usually in one of them and checking one at a time wastes turns:

          * the third-party providers configured here and whether each is active
            with valid credentials — the WhatsApp BSP, storage, analytics
          * the platform's own recent warnings and errors
          * how far the BigQuery export has got per table

        Credential values are never returned, only whether they are valid.
        """,
        parameters: [
          severity: [type: :string, doc: ~s(Only notifications of this severity, e.g. "Critical")],
          limit: [type: :pos_integer, default: 25, doc: "How many notifications, at most 100"]
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
      }
    ]
  end

  @doc "Reads one organisation lookup: who it is, whether the platform is healthy, its staff or its daily volume."
  @impl Glific.AI.Tool
  @spec run(String.t(), map()) :: {:ok, term()} | {:error, String.t()}
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

  def run("platform_health", args) do
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

    {:ok,
     %{
       providers: providers,
       notifications: notifications(args),
       bigquery: bigquery_jobs()
     }}
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

  @spec notifications(map()) :: [map()]
  defp notifications(args) do
    filter = maybe_put(%{}, :severity, args[:severity])

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
  end

  @spec bigquery_jobs() :: [map()]
  defp bigquery_jobs do
    Repo.get_organization_id()
    |> Jobs.get_bigquery_jobs()
    |> Enum.map(&%{table: &1.table, last_updated_at: &1.last_updated_at})
  end

  @spec maybe_put(map(), atom(), term()) :: map()
  defp maybe_put(filter, _key, nil), do: filter
  defp maybe_put(filter, key, value), do: Map.put(filter, key, value)
end
