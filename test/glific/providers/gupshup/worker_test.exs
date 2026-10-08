defmodule Glific.Providers.Gupshup.WorkerTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.Caches
  alias Glific.Fixtures
  alias Glific.Messages
  alias Glific.Providers.Gupshup.V3
  alias Glific.Settings.Language
  alias Glific.Templates.SessionTemplate

  setup %{organization_id: organization_id} = attrs do
    Application.put_env(:glific, :gupshup_v3_req_plug, {Req.Test, V3.ApiClient})
    Caches.set(organization_id, "partner_app_token", "cached-app-token")

    on_exit(fn -> Application.delete_env(:glific, :gupshup_v3_req_plug) end)

    {:ok, template} =
      %SessionTemplate{}
      |> SessionTemplate.changeset(%{
        label: "Feedback form",
        shortcode: "feedback_form",
        body: "Hi {{1}}, tell us how we did",
        type: :text,
        is_hsm: true,
        status: "APPROVED",
        number_parameters: 1,
        language_id: 1,
        organization_id: organization_id,
        has_buttons: true,
        button_type: :whatsapp_form,
        buttons: [%{"type" => "FLOW", "text" => "Open form", "flow_id" => "1787478395302778"}]
      })
      |> Repo.insert()

    %{template: template, contact: Fixtures.contact_fixture(attrs)}
  end

  test "a WhatsApp form template is sent through V3 with a flow_token when the flag is on",
       %{organization_id: organization_id, template: template, contact: contact} do
    FunWithFlags.enable(:is_gupshup_v3_template_enabled,
      for_actor: %{organization_id: organization_id}
    )

    test_pid = self()

    Req.Test.stub(V3.ApiClient, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request_body = Jason.decode!(body)
      send(test_pid, {:v3_request, conn.request_path, request_body})
      Req.Test.json(conn, %{"messages" => [%{"id" => "gupshup-v3-id"}]})
    end)

    {:ok, message} =
      Messages.create_and_send_hsm_message(%{
        template_id: template.id,
        receiver_id: contact.id,
        parameters: ["Asha"]
      })

    Oban.drain_queue(queue: :gupshup)

    assert_received {:v3_request, "/partner/app/" <> _, request_body}

    assert %{
             "to" => phone,
             "template" => %{
               "name" => "feedback_form",
               "language" => %{"code" => language_code},
               "components" => [
                 %{"type" => "body", "parameters" => [%{"text" => "Asha"}]},
                 %{
                   "sub_type" => "flow",
                   "parameters" => [%{"action" => %{"flow_token" => flow_token}}]
                 }
               ]
             }
           } = request_body

    assert phone == contact.phone
    assert language_code == Repo.get!(Language, 1).locale
    assert is_binary(flow_token) and flow_token != to_string(message.id)

    sent_message = Messages.get_message!(message.id)
    assert sent_message.bsp_message_id == "gupshup-v3-id"
    assert sent_message.bsp_status == :enqueued

    FunWithFlags.disable(:is_gupshup_v3_template_enabled,
      for_actor: %{organization_id: organization_id}
    )
  end

  test "a WhatsApp form template stays on V2 when the flag is off",
       %{organization_id: organization_id, template: template, contact: contact} do
    FunWithFlags.disable(:is_gupshup_v3_template_enabled,
      for_actor: %{organization_id: organization_id}
    )

    Tesla.Mock.mock(fn
      %{method: :post, url: url} ->
        assert url =~ "/template/msg"

        %Tesla.Env{
          status: 200,
          body: Jason.encode!(%{"status" => "submitted", "messageId" => "gupshup-v2-id"})
        }
    end)

    {:ok, message} =
      Messages.create_and_send_hsm_message(%{
        template_id: template.id,
        receiver_id: contact.id,
        parameters: ["Asha"]
      })

    Oban.drain_queue(queue: :gupshup)

    assert Messages.get_message!(message.id).bsp_message_id == "gupshup-v2-id"
  end
end
