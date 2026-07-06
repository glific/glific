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
        %{name: "🖥️ Node", value: to_string(node()), inline: false}
      ],
      footer: %{text: "Gigalixir rolling deployment"},
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Discord.post_embed(embed, :discord_deployment_webhook_url)
  end

  # `:gigalixir_app_name`/`:environment` app config are both compile-time constants
  # baked into the release and don't distinguish e.g. staging from production —
  # every Gigalixir app builds with MIX_ENV=prod. The node name, which Gigalixir
  # itself sets per-app for libcluster (e.g. "glific-staging@10.56.21.128"), is the
  # one value here that reliably reflects which app actually deployed.
  @spec app_name() :: String.t()
  defp app_name do
    node()
    |> to_string()
    |> String.split("@")
    |> List.first()
  end
end
