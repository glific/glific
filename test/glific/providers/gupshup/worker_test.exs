defmodule Glific.Providers.Gupshup.WorkerTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.Caches
  alias Glific.Fixtures
  alias Glific.Messages
  alias Glific.Messages.Message
  alias Glific.Providers.Gupshup.V3
  alias Glific.Providers.Gupshup.Worker
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

  test "a V3 send with a translation that no longer exists marks the message errored",
       %{organization_id: organization_id, template: template, contact: contact} do
    FunWithFlags.enable(:is_gupshup_v3_template_enabled,
      for_actor: %{organization_id: organization_id}
    )

    Req.Test.stub(V3.ApiClient, fn _conn -> flunk("no V3 request should be sent") end)

    message = Fixtures.message_fixture(%{flow: :outbound, receiver_id: contact.id})

    attrs =
      template
      |> form_template_attrs()
      |> Map.put("template_uuid", Ecto.UUID.generate())

    assert :ok = perform_send(message, contact, attrs)
    assert Messages.get_message!(message.id).bsp_status == :error

    FunWithFlags.disable(:is_gupshup_v3_template_enabled,
      for_actor: %{organization_id: organization_id}
    )
  end

  test "a translated WhatsApp form template is sent in the translation's language",
       %{organization_id: organization_id, template: template, contact: contact} do
    FunWithFlags.enable(:is_gupshup_v3_template_enabled,
      for_actor: %{organization_id: organization_id}
    )

    translation_uuid = Ecto.UUID.generate()

    {:ok, template} =
      template
      |> SessionTemplate.changeset(%{translations: %{"2" => %{"uuid" => translation_uuid}}})
      |> Repo.update()

    test_pid = self()

    Req.Test.stub(V3.ApiClient, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request_body = Jason.decode!(body)
      send(test_pid, {:v3_request, request_body})
      Req.Test.json(conn, %{"messages" => [%{"id" => "gupshup-v3-id"}]})
    end)

    message = Fixtures.message_fixture(%{flow: :outbound, receiver_id: contact.id})

    attrs =
      template
      |> form_template_attrs()
      |> Map.put("template_uuid", translation_uuid)

    assert :ok = perform_send(message, contact, attrs)

    assert_received {:v3_request, %{"template" => %{"language" => %{"code" => language_code}}}}
    assert language_code == Repo.get!(Language, 2).locale

    FunWithFlags.disable(:is_gupshup_v3_template_enabled,
      for_actor: %{organization_id: organization_id}
    )
  end

  test "a media WhatsApp form template is sent through V3 with its media header",
       %{organization_id: organization_id, template: template, contact: contact} do
    FunWithFlags.enable(:is_gupshup_v3_template_enabled,
      for_actor: %{organization_id: organization_id}
    )

    test_pid = self()

    Req.Test.stub(V3.ApiClient, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request_body = Jason.decode!(body)
      send(test_pid, {:v3_request, request_body})
      Req.Test.json(conn, %{"messages" => [%{"id" => "gupshup-v3-id"}]})
    end)

    message = Fixtures.message_fixture(%{flow: :outbound, receiver_id: contact.id})
    attrs = template |> form_template_attrs() |> Map.put("template_type", "image")
    media = Jason.encode!(%{"type" => "image", "originalUrl" => "https://example.com/a.png"})

    assert :ok = perform_send(message, contact, attrs, %{"message" => media})

    assert_received {:v3_request, %{"template" => %{"components" => [header | _]}}}

    assert header == %{
             "type" => "header",
             "parameters" => [
               %{"type" => "image", "image" => %{"link" => "https://example.com/a.png"}}
             ]
           }

    FunWithFlags.disable(:is_gupshup_v3_template_enabled,
      for_actor: %{organization_id: organization_id}
    )
  end

  test "an HSM message without a template is sent as a plain message", %{contact: contact} do
    Tesla.Mock.mock(fn
      %{method: :post, url: url} ->
        refute url =~ "/template/msg"

        %Tesla.Env{
          status: 200,
          body: Jason.encode!(%{"status" => "submitted", "messageId" => "gupshup-message-id"})
        }
    end)

    message = Fixtures.message_fixture(%{flow: :outbound, receiver_id: contact.id})

    assert :ok = perform_send(message, contact, %{"is_hsm" => true})
    assert Messages.get_message!(message.id).bsp_message_id == "gupshup-message-id"
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

  defp form_template_attrs(template) do
    %{
      "is_hsm" => true,
      "button_type" => "whatsapp_form",
      "template_id" => template.id,
      "template_uuid" => template.uuid,
      "template_type" => "text",
      "params" => ["Asha"]
    }
  end

  defp perform_send(message, contact, attrs, payload \\ %{}) do
    message_args = message |> Message.to_minimal_map() |> Jason.encode!() |> Jason.decode!()

    perform_job(Worker, %{
      "message" => message_args,
      "payload" => Map.put(payload, "destination", contact.phone),
      "attrs" => attrs,
      "organization_id" => message.organization_id
    })
  end
end
