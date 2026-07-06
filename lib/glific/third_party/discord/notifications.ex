defmodule Glific.ThirdParty.Discord.Notifications do
  @moduledoc """
  Builds and sends domain-specific Discord notifications.
  """

  alias Glific.Partners.Organization
  alias Glific.ThirdParty.Discord

  @doc """
  Sends a Discord embed notifying Glific developers that an organization
  has requested access to the AI Evaluations feature.
  """
  @spec send_eval_access_request(Organization.t()) :: :ok | {:error, String.t()}
  def send_eval_access_request(%Organization{} = organization) do
    login_url = "https://#{organization.shortcode}.#{Glific.base_domain()}"

    embed = %{
      title: "🤖 AI Evaluations Access Request",
      description:
        "An organization has requested access to the **AI Evaluations** feature.\nPlease review and enable the feature flag for this organization.",
      color: 0x5865F2,
      fields: [
        %{name: "🏢 Name", value: organization.name, inline: true},
        %{name: "🔑 Shortcode", value: organization.shortcode, inline: true},
        %{name: "📧 Email", value: organization.email, inline: false},
        %{name: "🔗 Login URL", value: "[#{login_url}]", inline: false}
      ],
      footer: %{text: "@Glific Developers — action required"},
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Discord.post_embed(embed)
  end

  @doc """
  Sends a Discord embed notifying Glific developers that an organization's
  AI Evaluations access request has been approved.
  """
  @spec send_eval_access_approved(Organization.t()) :: :ok | {:error, String.t()}
  def send_eval_access_approved(%Organization{} = organization) do
    login_url = "https://#{organization.shortcode}.#{Glific.base_domain()}"

    embed = %{
      title: "✅ AI Evaluations Access Approved",
      description: "An organization has been granted access to the **AI Evaluations** feature.",
      color: 0x57F287,
      fields: [
        %{name: "🏢 Name", value: organization.name, inline: true},
        %{name: "🔑 Shortcode", value: organization.shortcode, inline: true},
        %{name: "📧 Email", value: organization.email, inline: false},
        %{name: "🔗 Login URL", value: "[#{login_url}]", inline: false}
      ],
      footer: %{text: "@Glific Developers — access granted"},
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Discord.post_embed(embed)
  end

  @doc """
  Sends a Discord embed notifying Glific developers that a deployment's new
  revision has become healthy (i.e. the Endpoint has started accepting
  connections). Called once from the supervisor tree right after
  `GlificWeb.Endpoint` starts, per Gigalixir's recommended zero-downtime
  rollout pattern: a revision that never becomes healthy never reaches this
  code, so this only ever reports success — failed rollouts still need to be
  watched via `gigalixir ps` or log drains.
  """
  @spec send_deployment_healthy() :: :ok | {:error, String.t()}
  def send_deployment_healthy do
    embed = %{
      title: "🚀 Deployment Healthy",
      description: "A new revision has passed health checks and is now serving traffic.",
      color: 0x57F287,
      fields: [
        %{name: "🏷️ App", value: app_name(), inline: true},
        %{name: "🔀 SHA", value: release_sha(), inline: true},
        %{name: "🔖 Release", value: release_version(), inline: true},
        %{name: "🖥️ Node", value: to_string(node()), inline: false}
      ],
      footer: %{text: "Gigalixir rolling deployment"},
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Discord.post_embed(embed, :discord_deployment_webhook_url)
  end

  # Note: `GIGALIXIR_APP_NAME` (single underscore) is a *different*, reserved
  # variable Gigalixir uses internally for the release binary name (always
  # "prod" for this app) — do not confuse it with `GIGALIXIR__APP_NAME` below.

  @spec app_name() :: String.t()
  defp app_name, do: env_or_fallback(:gigalixir_release_app_name, &node_name/0)

  @spec release_sha() :: String.t()
  defp release_sha, do: env_or_fallback(:gigalixir_release_sha, fn -> "unknown" end)

  @spec release_version() :: String.t()
  defp release_version, do: env_or_fallback(:gigalixir_release_version, fn -> "unknown" end)

  @spec env_or_fallback(atom(), (-> String.t())) :: String.t()
  defp env_or_fallback(config_key, fallback) do
    case Application.get_env(:glific, config_key) do
      value when is_binary(value) and value != "" -> value
      _ -> fallback.()
    end
  end

  @spec node_name() :: String.t()
  defp node_name, do: node() |> to_string() |> String.split("@") |> List.first()
end
