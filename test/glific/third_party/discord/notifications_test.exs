defmodule Glific.ThirdParty.Discord.NotificationsTest do
  @moduledoc false
  use Glific.DataCase, async: true

  alias Glific.ThirdParty.Discord.Notifications

  describe "send_eval_access_request/1" do
    test "posts an embed with organization details to Discord", %{organization_id: organization_id} do
      Application.put_env(:glific, :discord_webhook_url, "https://discord.test/webhook")
      on_exit(fn -> Application.delete_env(:glific, :discord_webhook_url) end)

      test_pid = self()

      Tesla.Mock.mock(fn %{method: :post} = env ->
        send(test_pid, {:discord_called, env.body})
        %Tesla.Env{status: 200, body: ""}
      end)

      organization = Glific.Partners.organization(organization_id)
      assert :ok = Notifications.send_eval_access_request(organization)

      assert_received {:discord_called, body}
      decoded = Jason.decode!(body)
      [embed] = decoded["embeds"]

      assert embed["title"] =~ "AI Evaluations Access Request"
      assert embed["description"] =~ "AI Evaluations"

      field_values = Enum.map(embed["fields"], & &1["value"])
      assert Enum.any?(field_values, &(&1 == organization.name))
      assert Enum.any?(field_values, &(&1 == organization.shortcode))
      assert Enum.any?(field_values, &(&1 == organization.email))
    end

    test "returns ok silently when webhook URL is not configured", %{
      organization_id: organization_id
    } do
      Application.delete_env(:glific, :discord_webhook_url)

      organization = Glific.Partners.organization(organization_id)
      assert :ok = Notifications.send_eval_access_request(organization)
    end
  end

  describe "send_eval_access_approved/1" do
    test "posts an approved embed with organization details to Discord", %{
      organization_id: organization_id
    } do
      Application.put_env(:glific, :discord_webhook_url, "https://discord.test/webhook")
      on_exit(fn -> Application.delete_env(:glific, :discord_webhook_url) end)

      test_pid = self()

      Tesla.Mock.mock(fn %{method: :post} = env ->
        send(test_pid, {:discord_called, env.body})
        %Tesla.Env{status: 200, body: ""}
      end)

      organization = Glific.Partners.organization(organization_id)
      assert :ok = Notifications.send_eval_access_approved(organization)

      assert_received {:discord_called, body}
      decoded = Jason.decode!(body)
      [embed] = decoded["embeds"]

      assert embed["title"] =~ "AI Evaluations Access Approved"
      assert embed["description"] =~ "AI Evaluations"

      field_values = Enum.map(embed["fields"], & &1["value"])
      assert Enum.any?(field_values, &(&1 == organization.name))
      assert Enum.any?(field_values, &(&1 == organization.shortcode))
      assert Enum.any?(field_values, &(&1 == organization.email))
    end

    test "returns ok silently when webhook URL is not configured", %{
      organization_id: organization_id
    } do
      Application.delete_env(:glific, :discord_webhook_url)

      organization = Glific.Partners.organization(organization_id)
      assert :ok = Notifications.send_eval_access_approved(organization)
    end
  end
end
