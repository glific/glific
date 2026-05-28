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
        %{name: "🔗 Login URL", value: "[#{login_url}](#{login_url})", inline: false}
      ],
      footer: %{text: "@Glific Developers — action required"},
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Discord.post_embed(embed)
  end
end
