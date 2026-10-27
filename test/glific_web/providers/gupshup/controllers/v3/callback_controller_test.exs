defmodule GlificWeb.Providers.Gupshup.Controllers.V3.CallbackControllerTest do
  use GlificWeb.ConnCase
  use Oban.Testing, repo: Glific.Repo

  import Ecto.Query
  import ExUnit.CaptureLog
  import Mock

  alias Glific.Contacts
  alias Glific.Fixtures
  alias Glific.Messages
  alias Glific.Messages.Message
  alias Glific.Partners
  alias Glific.Processor.MessageWorker
  alias Glific.Repo
  alias Glific.Seeds.SeedsDev
  alias Glific.Templates
  alias Glific.WhatsappForms
  alias Glific.WhatsappForms.WhatsappFormResponse

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    :ok
  end

  describe "statuses" do
    setup do
      gupshup_id = Ecto.UUID.generate()

      {:ok, message} =
        %{bsp_message_id: gupshup_id}
        |> Fixtures.message_fixture()
        |> Messages.update_message(%{bsp_status: :error})

      %{message: message, gupshup_id: gupshup_id}
    end

    for {meta_status, bsp_status} <- [
          {"enqueued", :enqueued},
          {"sent", :sent},
          {"delivered", :delivered},
          {"read", :read}
        ] do
      test "#{meta_status} status sets bsp_status to #{bsp_status}",
           %{conn: conn, message: message, gupshup_id: gupshup_id} do
        payload = meta_status_payload(%{"gs_id" => gupshup_id, "status" => unquote(meta_status)})

        conn = post(conn, "/gupshup", payload)
        assert response(conn, 200) == ""
        assert Messages.get_message!(message.id).bsp_status == unquote(bsp_status)
      end
    end

    test "status with only the WhatsApp id leaves the message untouched",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      payload = meta_status_payload(%{"id" => gupshup_id, "status" => "delivered"})

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == message.bsp_status
    end

    test "updates every status in a batched callback",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      other_gupshup_id = Ecto.UUID.generate()
      other_message = Fixtures.message_fixture(%{bsp_message_id: other_gupshup_id})

      payload =
        meta_status_payload([
          %{"gs_id" => gupshup_id, "status" => "read"},
          %{"gs_id" => other_gupshup_id, "status" => "delivered"}
        ])

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == :read
      assert Messages.get_message!(other_message.id).bsp_status == :delivered
    end

    test "failed status marks the message as error and keeps the error code",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      {:ok, message} = Messages.update_message(message, %{bsp_status: :sent, errors: %{}})

      payload =
        meta_status_payload(%{
          "gs_id" => gupshup_id,
          "status" => "failed",
          "errors" => [
            %{
              "code" => 131_049,
              "title" =>
                "This message was not delivered to maintain healthy ecosystem engagement."
            }
          ]
        })

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""

      message = Messages.get_message!(message.id)
      assert message.bsp_status == :error
      assert get_in(message.errors, ["payload", "payload", "code"]) == 131_049
      assert [%{"code" => 131_049}] = message.errors["errors"]
    end

    test "failed status with a Meta error code is recorded without contact side effects",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      {:ok, message} = Messages.update_message(message, %{bsp_status: :sent})

      contact_status = Contacts.get_contact!(message.contact_id).status

      payload =
        meta_status_payload(%{
          "gs_id" => gupshup_id,
          "status" => "failed",
          "errors" => [%{"code" => 131_026, "title" => "Message undeliverable"}]
        })

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""

      message = Messages.get_message!(message.id)
      assert message.bsp_status == :error
      assert get_in(message.errors, ["payload", "payload", "code"]) == 131_026
      assert Contacts.get_contact!(message.contact_id).status == contact_status
    end

    test "failed status with top-level code and reason marks the contact invalid",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      {:ok, message} = Messages.update_message(message, %{bsp_status: :sent})

      payload =
        meta_status_payload(%{
          "gs_id" => gupshup_id,
          "status" => "failed",
          "code" => "1002",
          "reason" => "Number does not exist on WhatsApp"
        })

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""

      message = Messages.get_message!(message.id)
      assert get_in(message.errors, ["payload", "payload", "code"]) == 1002

      assert get_in(message.errors, ["payload", "payload", "reason"]) ==
               "Number does not exist on WhatsApp"

      contact = Contacts.get_contact!(message.contact_id)
      assert contact.status == :invalid
    end

    test "failed status keeps a non-numeric error code as is",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      {:ok, message} = Messages.update_message(message, %{bsp_status: :sent})

      payload =
        meta_status_payload(%{
          "gs_id" => gupshup_id,
          "status" => "failed",
          "code" => "E_UNKNOWN",
          "reason" => "Unknown error"
        })

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""

      message = Messages.get_message!(message.id)
      assert get_in(message.errors, ["payload", "payload", "code"]) == "E_UNKNOWN"
    end

    test "status without a status field leaves the message untouched",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      payload = meta_status_payload(%{"gs_id" => gupshup_id})

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == message.bsp_status
    end

    test "entry without changes leaves the message untouched",
         %{conn: conn, message: message} do
      payload = %{"object" => "whatsapp_business_account", "entry" => [%{"id" => "1234567890"}]}

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == message.bsp_status
    end

    test "unknown status leaves the message untouched",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      payload = meta_status_payload(%{"gs_id" => gupshup_id, "status" => "deleted"})

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == message.bsp_status
    end

    test "status without a message id is skipped",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      payload =
        meta_status_payload([
          %{"status" => "read"},
          %{"gs_id" => gupshup_id, "status" => "read"}
        ])

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == :read
    end

    test "entry payload with an empty statuses list leaves the message untouched",
         %{conn: conn, message: message} do
      payload = meta_status_payload([])

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == message.bsp_status
    end

    test "inactive organization does not update the status",
         %{conn: conn, message: message, gupshup_id: gupshup_id} do
      organization = Partners.organization(conn.assigns[:organization_id])
      {:ok, _organization} = Partners.update_organization(organization, %{status: :suspended})

      payload = meta_status_payload(%{"gs_id" => gupshup_id, "status" => "read"})

      conn = post(conn, "/gupshup", payload)
      assert response(conn, 200) == ""
      assert Messages.get_message!(message.id).bsp_status == message.bsp_status
    end
  end

  describe "whatsapp_form_response" do
    test "Incoming WhatsApp form response should be stored in the database with whatsapp_response_id",
         %{conn: conn, user: user} do
      Tesla.Mock.mock(fn
        %{method: :post, url: url} ->
          cond do
            String.contains?(url, "/flows") ->
              %Tesla.Env{
                status: 201,
                body: %{id: "1787478395302778", status: "success", validation_errors: []}
              }

            String.contains?(url, "subscription") ->
              %Tesla.Env{
                status: 200,
                body: "{\"status\":\"success\",\"subscription\":{\"active\":true}}"
              }
          end
      end)

      {:ok, temp} =
        Templates.create_session_template(%{
          label: "Whatsapp Form Template",
          type: :text,
          body: "Hello World",
          language_id: 1,
          organization_id: conn.assigns[:organization_id],
          uuid: "3982792f-a178-442d-be4b-3eadbb804726",
          buttons: [
            %{
              "text" => "RATE",
              "type" => "FLOW",
              "flow_id" => "1787478395302778",
              "flow_action" => "NAVIGATE",
              "navigate_screen" => "RATE"
            }
          ]
        })

      {:ok, _message} =
        Messages.create_message(%{
          body: "Hello| [Open] ",
          flow: :outbound,
          type: :text,
          sender_id: 1,
          receiver_id: 2,
          contact_id: 1,
          organization_id: conn.assigns[:organization_id],
          bsp_message_id: "0e74fb92-eb8a-415a-bccd-42ee768665e0",
          template_id: temp.id
        })

      {:ok, _wa_form} =
        WhatsappForms.create_whatsapp_form(
          %{
            name: "Customer Feedback Form",
            meta_flow_id: "1787478395302778",
            form_json: %{
              "screens" => []
            },
            categories: ["other"],
            description: "A form to collect customer feedback",
            organization_id: conn.assigns[:organization_id]
          },
          user
        )

      payload = %{
        "entry" => [
          %{
            "changes" => [
              %{
                "field" => "messages",
                "value" => %{
                  "contacts" => [
                    %{
                      "profile" => %{"name" => "Smit"},
                      "wa_id" => "919917443994"
                    }
                  ],
                  "messages" => [
                    %{
                      "context" => %{
                        "from" => "919917443994",
                        "gs_id" => "0e74fb92-eb8a-415a-bccd-42ee768665e0",
                        "id" => "031AGDymvDNTGOEfndITwW",
                        "meta_msg_id" =>
                          "wamid.HBgMOTE5NDI1MDEwNDQ5FQIAERgSNzY4MjM3OEU5RDBFQUY1MDNFAA=="
                      },
                      "from" => "919917443994",
                      "id" => "wamid.HBgMOTE5NDI1MDEwNDQ5FQIAEhgUM0E3MzZCRDU0NTNCRTIxQUFFMzkA",
                      "interactive" => %{
                        "nfm_reply" => %{
                          "body" => "Sent",
                          "name" => "flow",
                          "response_json" =>
                            "{\"screen_1_Purchase_experience_0\":\"0_Excellent\",\"screen_1_Delivery_and_setup_1\":\"2_Average\",\"screen_0_Choose_one_0\":\"0_Yes\",\"flow_token\":\"unused\",\"screen_1_Customer_service_2\":\"0_Excellent\"}"
                        },
                        "type" => "nfm_reply"
                      },
                      "timestamp" => "1763015605",
                      "type" => "interactive"
                    }
                  ]
                }
              }
            ],
            "id" => "122037724131744"
          }
        ]
      }

      conn2 = post(conn, "/gupshup", payload)
      assert conn2.halted

      bsp_message_id = "wamid.HBgMOTE5NDI1MDEwNDQ5FQIAEhgUM0E3MzZCRDU0NTNCRTIxQUFFMzkA"

      {:ok, message} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      message = Repo.preload(message, [:sender, :media])
      assert_enqueued(worker: MessageWorker, prefix: "global")

      assert message.whatsapp_form_response_id != nil
      assert message.flow == :inbound
      assert message.sender.phone == "919917443994"
      assert message.context_id == "0e74fb92-eb8a-415a-bccd-42ee768665e0"

      {:ok, form_response} =
        Repo.fetch_by(WhatsappFormResponse, %{id: message.whatsapp_form_response_id})

      assert form_response.raw_response != nil
    end

    test "WhatsApp form response with no matching form should not be stored", %{conn: conn} do
      {:ok, _temp} =
        Templates.create_session_template(%{
          label: "Whatsapp Form Template",
          type: :text,
          body: "Hello World",
          language_id: 1,
          organization_id: conn.assigns[:organization_id],
          bsp_id: "3982792f-a178-442d-be4b-3eadbb804726",
          buttons: [
            %{
              "text" => "RATE",
              "type" => "FLOW",
              "flow_id" => "1787478395302778",
              "flow_action" => "NAVIGATE",
              "navigate_screen" => "RATE"
            }
          ]
        })

      payload = %{
        "entry" => [
          %{
            "changes" => [
              %{
                "field" => "messages",
                "value" => %{
                  "contacts" => [
                    %{
                      "profile" => %{"name" => "Smit"},
                      "wa_id" => "919917443994"
                    }
                  ],
                  "messages" => [
                    %{
                      "context" => %{
                        "from" => "919917443994",
                        "gs_id" => "0e74fb92-eb8a-415a-bccd-42ee768665e0",
                        "id" => "031AGDymvDNTGOEfndITwW",
                        "meta_msg_id" =>
                          "wamid.HBgMOTE5NDI1MDEwNDQ5FQIAERgSNzY4MjM3OEU5RDBFQUY1MDNFAA=="
                      },
                      "from" => "919917443994",
                      "id" => "wamid.HBgMOTE5NDI1MDEwNDQ5FQIAEhgUM0E3MzZCRDU0NTNCRTIxQUFFMzkA",
                      "interactive" => %{
                        "nfm_reply" => %{
                          "body" => "Sent",
                          "name" => "flow",
                          "response_json" =>
                            "{\"screen_1_Purchase_experience_0\":\"0_Excellent\",\"screen_1_Delivery_and_setup_1\":\"2_Average\",\"screen_0_Choose_one_0\":\"0_Yes\",\"flow_token\":\"unused\",\"screen_1_Customer_service_2\":\"0_Excellent\"}"
                        },
                        "type" => "nfm_reply"
                      },
                      "timestamp" => "1763015605",
                      "type" => "interactive"
                    }
                  ]
                }
              }
            ],
            "id" => "122037724131744"
          }
        ]
      }

      conn2 = post(conn, "/gupshup", payload)
      assert conn2.halted

      bsp_message_id = "wamid.HBgMOTE5NDI1MDEwNDQ5FQIAEhgUM0E3MzZCRDU0NTNCRTIxQUFFMzkA"

      {:error, error} =
        Repo.fetch_by(Message, %{
          bsp_message_id: bsp_message_id,
          organization_id: conn.assigns[:organization_id]
        })

      assert error == ["Elixir.Glific.Messages.Message", "Resource not found"]
    end

    test "WhatsApp form response without context returns 200 and stores nothing",
         %{conn: conn} do
      bsp_message_id = "wamid.HBgMOTE5NDI1MDEwNDQ5FQIAEhgUM0E3MzZCRDU0NTNCRTIxQUFFNDAA"

      level = Logger.level()
      Logger.configure(level: :error)
      on_exit(fn -> Logger.configure(level: level) end)

      log =
        capture_log(fn ->
          conn2 =
            post(
              conn,
              "/gupshup",
              whatsapp_form_response_payload(bsp_message_id, nil)
            )

          assert conn2.status == 200
        end)

      assert log =~
               "Failed to create WhatsApp form response: bsp_message_id=#{bsp_message_id}, reason=\"WhatsApp form response has no context id\""

      assert {:error, _} =
               Repo.fetch_by(Message, %{
                 bsp_message_id: bsp_message_id,
                 organization_id: conn.assigns[:organization_id]
               })

      assert Repo.aggregate(WhatsappFormResponse, :count) == 0
    end

    test "duplicate WhatsApp form response stores a single response and message",
         %{conn: conn} do
      {:ok, whatsapp_form} = Fixtures.whatsapp_form_fixture()

      organization_id = conn.assigns[:organization_id]

      {:ok, template} =
        Templates.create_session_template(%{
          label: "Whatsapp Form Template",
          type: :text,
          body: "Hello World",
          language_id: 1,
          organization_id: organization_id,
          uuid: "3982792f-a178-442d-be4b-3eadbb804727",
          buttons: [
            %{
              "text" => "RATE",
              "type" => "FLOW",
              "flow_id" => whatsapp_form.meta_flow_id,
              "flow_action" => "NAVIGATE",
              "navigate_screen" => "RATE"
            }
          ]
        })

      {:ok, _message} =
        Messages.create_message(%{
          body: "Hello| [Open] ",
          flow: :outbound,
          type: :text,
          sender_id: 1,
          receiver_id: 2,
          contact_id: 1,
          organization_id: organization_id,
          bsp_message_id: "0e74fb92-eb8a-415a-bccd-42ee768665e1",
          template_id: template.id
        })

      bsp_message_id = "wamid.HBgMOTE5NDI1MDEwNDQ5FQIAEhgUM0E3MzZCRDU0NTNCRTIxQUFFNDEA"

      payload =
        whatsapp_form_response_payload(bsp_message_id, %{
          "from" => "919917443994",
          "gs_id" => "0e74fb92-eb8a-415a-bccd-42ee768665e1",
          "id" => "031AGDymvDNTGOEfndITwX"
        })

      assert post(conn, "/gupshup", payload).status == 200

      with_mock Elixir.Appsignal,
                [:passthrough],
                increment_counter: fn _, _, _ -> :ok end do
        assert post(conn, "/gupshup", payload).status == 200

        assert called(
                 Elixir.Appsignal.increment_counter(
                   "duplicate_inbound_message",
                   1,
                   %{org_id: organization_id}
                 )
               )
      end

      assert [_message] =
               Repo.all(from(m in Message, where: m.bsp_message_id == ^bsp_message_id))

      assert Repo.aggregate(WhatsappFormResponse, :count) == 1

      assert [_job] =
               all_enqueued(worker: Glific.WhatsappForms.WhatsappFormWorker, prefix: "global")
    end
  end

  describe "duplicate callbacks" do
    test "a V2 failure arriving after the V3 one still runs the Gupshup error handling",
         %{conn: conn} do
      gupshup_id = Ecto.UUID.generate()

      {:ok, message} =
        %{bsp_message_id: gupshup_id}
        |> Fixtures.message_fixture()
        |> Messages.update_message(%{bsp_status: :sent})

      v3_payload =
        meta_status_payload(%{
          "gs_id" => gupshup_id,
          "status" => "failed",
          "errors" => [%{"code" => 131_026, "title" => "Message undeliverable"}]
        })

      assert post(conn, "/gupshup", v3_payload).status == 200
      assert Contacts.get_contact!(message.contact_id).status != :invalid

      v2_payload = %{
        "app" => "Glific App",
        "type" => "message-event",
        "version" => 2,
        "payload" => %{
          "type" => "failed",
          "gsId" => gupshup_id,
          "id" => "gBEGkZkXRDmUAgl5FpzpjNgI5Co",
          "payload" => %{"ts" => "1592311836", "code" => 1002}
        }
      }

      assert post(conn, "/gupshup", v2_payload).status == 200

      message = Messages.get_message!(message.id)
      assert get_in(message.errors, ["payload", "payload", "code"]) == 1002
      assert Contacts.get_contact!(message.contact_id).status == :invalid
    end

    test "a failure already received in V2 format is not processed again from V3",
         %{conn: conn} do
      gupshup_id = Ecto.UUID.generate()

      {:ok, message} =
        %{bsp_message_id: gupshup_id}
        |> Fixtures.message_fixture()
        |> Messages.update_message(%{bsp_status: :sent})

      v2_payload = %{
        "app" => "Glific App",
        "type" => "message-event",
        "version" => 2,
        "payload" => %{
          "type" => "failed",
          "gsId" => gupshup_id,
          "id" => "gBEGkZkXRDmUAgl5FpzpjNgI5Co",
          "payload" => %{"ts" => "1592311836", "code" => 1002}
        }
      }

      assert post(conn, "/gupshup", v2_payload).status == 200
      contact = Contacts.get_contact!(message.contact_id)
      assert contact.status == :invalid
      {:ok, _contact} = Contacts.update_contact(contact, %{status: :valid})

      v3_payload =
        meta_status_payload(%{
          "gs_id" => gupshup_id,
          "status" => "failed",
          "code" => "1002",
          "reason" => "Number does not exist on WhatsApp"
        })

      assert post(conn, "/gupshup", v3_payload).status == 200

      message = Messages.get_message!(message.id)
      assert get_in(message.errors, ["payload", "type"]) == "failed"
      assert Contacts.get_contact!(message.contact_id).status == :valid
    end
  end

  describe "dispatch" do
    setup do
      level = Logger.level()
      on_exit(fn -> Logger.configure(level: level) end)
      :ok
    end

    test "handles a status change and a form response change in the same callback",
         %{conn: conn} do
      gupshup_id = Ecto.UUID.generate()

      {:ok, message} =
        %{bsp_message_id: gupshup_id}
        |> Fixtures.message_fixture()
        |> Messages.update_message(%{bsp_status: :sent})

      form_bsp_message_id = "wamid.HBgMOTE5NDI1MDEwNDQ5FQIAEhgUM0E3MzZCRDU0NTNCRTIxQUFFNDIA"

      [form_change] =
        form_bsp_message_id
        |> whatsapp_form_response_payload(nil)
        |> get_in(["entry", Access.at(0), "changes"])

      [status_change] =
        %{"gs_id" => gupshup_id, "status" => "read"}
        |> meta_status_payload()
        |> get_in(["entry", Access.at(0), "changes"])

      payload = %{"entry" => [%{"changes" => [status_change, form_change]}]}

      Logger.configure(level: :error)

      log =
        capture_log(fn ->
          assert post(conn, "/gupshup", payload).status == 200
        end)

      assert Messages.get_message!(message.id).bsp_status == :read

      assert log =~
               "Failed to create WhatsApp form response: bsp_message_id=#{form_bsp_message_id}"
    end

    test "acknowledges a change it has no handler for", %{conn: conn} do
      payload = %{
        "object" => "whatsapp_business_account",
        "entry" => [
          %{
            "changes" => [
              %{"field" => "messages", "value" => %{"messaging_product" => "whatsapp"}}
            ]
          }
        ]
      }

      assert post(conn, "/gupshup", payload).status == 200
    end
  end

  defp whatsapp_form_response_payload(bsp_message_id, context) do
    message =
      %{
        "from" => "919917443994",
        "id" => bsp_message_id,
        "interactive" => %{
          "nfm_reply" => %{
            "body" => "Sent",
            "name" => "flow",
            "response_json" => "{\"screen_0_Choose_one_0\":\"0_Yes\",\"flow_token\":\"unused\"}"
          },
          "type" => "nfm_reply"
        },
        "timestamp" => "1763015605",
        "type" => "interactive"
      }
      |> then(fn message ->
        if context, do: Map.put(message, "context", context), else: message
      end)

    %{
      "entry" => [
        %{
          "changes" => [
            %{
              "field" => "messages",
              "value" => %{
                "contacts" => [%{"profile" => %{"name" => "Smit"}, "wa_id" => "919917443994"}],
                "messages" => [message]
              }
            }
          ],
          "id" => "122037724131744"
        }
      ]
    }
  end

  defp meta_status_payload(statuses) do
    statuses =
      statuses
      |> List.wrap()
      |> Enum.map(
        &Map.merge(%{"recipient_id" => "919999999999", "timestamp" => "1791897501"}, &1)
      )

    %{
      "object" => "whatsapp_business_account",
      "entry" => [
        %{
          "id" => "1234567890",
          "changes" => [
            %{
              "field" => "messages",
              "value" => %{"messaging_product" => "whatsapp", "statuses" => statuses}
            }
          ]
        }
      ]
    }
  end
end
