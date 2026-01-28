defmodule Glific.Processor.ConsumerFlowTest do
  use GlificWeb.ConnCase

  import Ecto.Query

  alias Glific.{
    Contacts,
    Contacts.Contact,
    Fixtures,
    Flows,
    Flows.Flow,
    Flows.FlowContext,
    Messages,
    Messages.Message,
    Processor.ConsumerFlow,
    Repo,
    Seeds.SeedsDev,
    Templates,
    WhatsappForms,
    WhatsappForms.WhatsappFormResponse
  }

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)
    SeedsDev.seed_contacts()
    SeedsDev.seed_messages()
    SeedsDev.seed_interactives()

    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 200,
          body:
            Jason.encode!(%{
              "name" => "Opted In Contact",
              "phone" => "A phone number"
            })
        }
    end)

    message_params = %{
      "payload" => %{
        "context" => %{"gsId" => nil, "id" => ""},
        "id" => "9f149409-1afa-4aed-b44a-2e4595ef4239",
        "payload" => %{
          "id" => "ceaecc2a-d76c-4bae-9e73-a0290ee0fe93",
          "reply" => "👍 1",
          "title" => "👍"
        },
        "sender" => %{"name" => "Glific Simulator One", "phone" => "9876543210_1"},
        "type" => "button_reply"
      },
      "type" => "message"
    }

    {:ok, %{message_params: message_params}}
  end

  @checks %{
    0 => "help",
    1 => "does not exist",
    2 => "still does not exist",
    3 => "2",
    4 => "language",
    5 => "no language",
    6 => "2",
    7 => "newcontact",
    8 => "👍",
    9 => "2",
    10 => "We are Glific",
    11 => "4"
  }
  @checks_size Enum.count(@checks)

  test "should start the flow" do
    state = ConsumerFlow.load_state(Fixtures.get_org_id())

    # keep track of current messages
    message_count = Repo.aggregate(Message, :count)

    sender = Repo.get_by(Contact, %{name: "Chrissy Cron"})

    Enum.map(
      0..(@checks_size - 1),
      fn c ->
        message =
          Fixtures.message_fixture(%{body: @checks[rem(c, @checks_size)], sender_id: sender.id})
          |> Repo.preload([:contact])

        ConsumerFlow.process_message({message, state}, message.body)
      end
    )

    new_message_count = Repo.aggregate(Message, :count)
    assert new_message_count > message_count + @checks_size
  end

  test "test draft flows" do
    state = ConsumerFlow.load_state(Fixtures.get_org_id())

    # keep track of current messages
    message_count = Repo.aggregate(Message, :count)

    sender = Repo.get_by(Contact, %{name: "Chrissy Cron"})

    message =
      Fixtures.message_fixture(%{body: "draft:help", sender_id: sender.id})
      |> Repo.preload([:contact])

    ConsumerFlow.process_message({message, state}, "drafthelp")

    new_message_count = Repo.aggregate(Message, :count)
    assert new_message_count > message_count + 1
  end

  test "test template flows" do
    state = ConsumerFlow.load_state(Fixtures.get_org_id())

    # keep track of current messages
    message_count = Repo.aggregate(Message, :count)

    sender = Repo.get_by(Contact, %{name: "Chrissy Cron"})

    message =
      Fixtures.message_fixture(%{body: "template:Direct with GPT", sender_id: sender.id})
      |> Repo.preload([:contact])

    ConsumerFlow.process_message({message, state}, "templatedirectwithgpt")

    new_message_count = Repo.aggregate(Message, :count)
    assert new_message_count > message_count + 1
  end

  @checks_1 [
    "optin",
    "👍",
    "optout",
    "1"
  ]

  defp send_messages(list, sender, receiver) do
    state = ConsumerFlow.load_state(Fixtures.get_org_id())

    Enum.map(
      list,
      fn c ->
        message =
          Fixtures.message_fixture(%{
            body: c,
            sender_id: sender.id,
            receiver_id: receiver.id
          })
          |> Map.put(:contact_id, sender.id)
          |> Map.put(:contact, sender)

        ConsumerFlow.process_message({message, state}, message.body)
      end
    )
  end

  test "check optin/optout sequence" do
    # keep track of current messages
    message_count = Repo.aggregate(Message, :count)

    {:ok, sender} =
      Repo.get_by(Contact, %{name: "Chrissy Cron"})
      |> Contacts.update_contact(%{phone: "919917443332"})

    receiver = Repo.get_by(Contact, %{name: "NGO Main Account"})

    send_messages(@checks_1, sender, receiver)

    # We should add check that there is a set of optin and optout message here
    new_message_count = Repo.aggregate(Message, :count)
    assert new_message_count > message_count + Enum.count(@checks_1)

    sender = Repo.get_by(Contact, %{name: "Chrissy Cron"})
    assert sender.optin_status == false
    assert !is_nil(sender.optout_time)
  end

  test "check regx flow sequence" do
    state = ConsumerFlow.load_state(Fixtures.get_org_id())

    # keep track of current messages
    message_count = Repo.aggregate(Message, :count)

    sender = Repo.get_by(Contact, %{name: "Chrissy Cron"})

    # The default regex config matches the word `unique_regex`
    message =
      Fixtures.message_fixture(%{body: "unique_regex", sender_id: sender.id})
      |> Repo.preload([:contact])

    ConsumerFlow.process_message({message, state}, message.body)

    new_message_count = Repo.aggregate(Message, :count)
    assert new_message_count > message_count + 1
  end

  test "should not start optin flow when flow is inactive" do
    state = ConsumerFlow.load_state(Fixtures.get_org_id())

    sender =
      Repo.get_by(Contact, %{name: "Chrissy Cron"})
      |> Contact.changeset(%{
        status: :invalid,
        optin_time: nil,
        optout_time: ~U[2023-12-22 12:00:00Z],
        optin_method: nil,
        optin_status: false,
        is_contact_replied: false
      })

    sender = Repo.update!(sender)

    flow =
      Repo.get_by(Flow, name: "Optin Workflow")
      |> Flow.changeset(%{is_active: false})
      |> Repo.update!()

    FlowContext
    |> Repo.delete_all(contact_id: sender.id, flow_id: flow.id)

    # Clearing the cache to ensure the flow reflects its inactive state
    Flows.update_cached_flow(flow, "published")

    message =
      Fixtures.message_fixture(%{body: "hey", sender_id: sender.id})
      |> Repo.preload([:contact])

    ConsumerFlow.process_message({message, state}, message.body)

    flow_context_after =
      Repo.get_by(FlowContext, contact_id: sender.id, flow_id: flow.id)

    assert flow_context_after == nil

    latest_message =
      Repo.one(
        from m in Message,
          where: m.sender_id == ^sender.id,
          order_by: [desc: m.inserted_at],
          limit: 1
      )

    assert latest_message.body == "hey"
  end

  test "received interactive msg node_id not present in flow, returns the non-updated context",
       %{
         conn: conn,
         message_params: message_params
       } = attrs do
    FunWithFlags.enable(:is_interactive_re_response_enabled,
      for_actor: %{organization_id: attrs.organization_id}
    )

    conn = post(conn, "/gupshup", message_params)
    assert conn.halted
    bsp_message_id = get_in(message_params, ["payload", "id"])

    {:ok, message} =
      Repo.fetch_by(Message, %{
        bsp_message_id: bsp_message_id,
        organization_id: conn.assigns[:organization_id]
      })

    assert message.bsp_status == :delivered

    [flow | _tail] = Glific.Flows.list_flows(%{filter: %{}})
    [keyword | _] = flow.keywords
    flow = Flow.get_loaded_flow(attrs.organization_id, "published", %{keyword: keyword})
    contact = Fixtures.contact_fixture()
    {:ok, flow_context, _} = FlowContext.init_context(flow, contact, "published")
    state = ConsumerFlow.load_state(Fixtures.get_org_id())
    assert is_tuple(ConsumerFlow.continue_current_context(flow_context, message, "body", state))

    assert :error = Map.fetch(flow.uuid_map, message.interactive_content["id"])
  end

  test "received interactive msg node_id present in flow, returns the updated context",
       %{
         conn: conn,
         message_params: message_params
       } = attrs do
    FunWithFlags.enable(:is_interactive_re_response_enabled,
      for_actor: %{organization_id: attrs.organization_id}
    )

    conn = post(conn, "/gupshup", message_params)
    assert conn.halted
    bsp_message_id = get_in(message_params, ["payload", "id"])

    {:ok, message} =
      Repo.fetch_by(Message, %{
        bsp_message_id: bsp_message_id,
        organization_id: conn.assigns[:organization_id]
      })

    assert message.bsp_status == :delivered

    flow =
      Repo.get_by(Flow, name: "Optin Workflow")

    [keyword | _] = flow.keywords
    flow = Flow.get_loaded_flow(attrs.organization_id, "published", %{keyword: keyword})
    contact = Fixtures.contact_fixture()
    {:ok, flow_context, _} = FlowContext.init_context(flow, contact, "published")
    state = ConsumerFlow.load_state(Fixtures.get_org_id())
    assert is_tuple(ConsumerFlow.continue_current_context(flow_context, message, "body", state))

    new_context =
      Repo.get_by(FlowContext, contact_id: contact.id, flow_id: flow.id)

    # check the optin.json for more info. The message we send via webhook has reply 👍
    # according to it flow continues after continue_current_context and reach the end of flow
    assert new_context.node_uuid == "17b7c45e-89e6-4196-9250-6943163ab8eb"
    assert is_tuple(ConsumerFlow.continue_current_context(flow_context, message, "body", state))

    # even if run continue_context again, the flow is already finished
    refute is_nil(Repo.get_by(FlowContext, contact_id: contact.id, flow_id: flow.id).completed_at)
  end

  test "chooses correct wait_for_response, even if there are multiple of them",
       %{
         conn: conn,
         message_params: message_params
       } = attrs do
    FunWithFlags.enable(:is_interactive_re_response_enabled,
      for_actor: %{organization_id: attrs.organization_id}
    )

    # Refer int_msg_re_response.json

    # sending RCB as the response to the interactive template
    message_params =
      put_in(message_params, ["payload", "payload"], %{
        "id" => "62ff6da6-00f2-400d-ae43-253470d1a6be",
        "reply" => "RCB 1",
        "title" => "RCB"
      })

    conn2 = conn
    conn3 = conn
    conn = post(conn, "/gupshup", message_params)
    assert conn.halted
    bsp_message_id = get_in(message_params, ["payload", "id"])

    {:ok, message} =
      Repo.fetch_by(Message, %{
        bsp_message_id: bsp_message_id,
        organization_id: conn.assigns[:organization_id]
      })

    assert message.bsp_status == :delivered

    flow =
      Flow.get_loaded_flow(attrs.organization_id, "published", %{
        uuid: "0633e385-0625-4432-98f7-e780a73944aa"
      })

    contact = Fixtures.contact_fixture()
    {:ok, flow_context, _} = FlowContext.init_context(flow, contact, "published")
    state = ConsumerFlow.load_state(Fixtures.get_org_id())
    assert is_tuple(ConsumerFlow.continue_current_context(flow_context, message, "body", state))

    new_context =
      Repo.get_by(FlowContext, contact_id: contact.id, flow_id: flow.id)

    # check the int_msg_re_response.json for more info. The message we send via webhook has reply "RCB 1"
    # according to it flow continues after continue_current_context and reach the next wait for response
    # which is awaiting response for "what u think, who will win" (which is a normal send_msg node).
    assert new_context.node_uuid == "f54b0868-8fb0-42fd-a9fc-8e15274bcea9"

    # But we again send response from the first interactive msg
    message_params =
      put_in(message_params, ["payload", "payload"], %{
        "id" => "62ff6da6-00f2-400d-ae43-253470d1a6be",
        "reply" => "KKR 1",
        "title" => "KKR"
      })

    conn2 = post(conn2, "/gupshup", message_params)
    assert conn2.halted
    bsp_message_id = get_in(message_params, ["payload", "id"])

    {:ok, message} =
      Repo.fetch_by(Message, %{
        bsp_message_id: bsp_message_id,
        organization_id: attrs.organization_id
      })

    assert message.bsp_status == :delivered

    assert is_tuple(ConsumerFlow.continue_current_context(new_context, message, "body", state))

    new_context =
      Repo.get_by(FlowContext, contact_id: contact.id, flow_id: flow.id)

    # So flow resumes from the interactive msg and reaches the same wait_for_response node of
    # snd_msg node
    assert new_context.node_uuid == "f54b0868-8fb0-42fd-a9fc-8e15274bcea9"

    # This time we send a normal text response for the snd_msg node
    message_params = %{
      "payload" => %{
        "id" => "9f149409-1afa-4aed-b44a-2e4595ef4269",
        "payload" => %{"text" => "Yes"},
        "sender" => %{"name" => "Glific Simulator One", "phone" => "9876543210_1"},
        "type" => "text"
      },
      "type" => "message"
    }

    conn3 = post(conn3, "/gupshup", message_params)
    assert conn3.halted
    bsp_message_id = get_in(message_params, ["payload", "id"])

    {:ok, message} =
      Repo.fetch_by(Message, %{
        bsp_message_id: bsp_message_id,
        organization_id: attrs.organization_id
      })

    assert message.bsp_status == :delivered

    new_context =
      Repo.get_by(FlowContext, contact_id: contact.id, flow_id: flow.id)

    assert is_tuple(ConsumerFlow.continue_current_context(new_context, message, "body", state))

    new_context =
      Repo.get_by(FlowContext, contact_id: contact.id, flow_id: flow.id)

    # Flow finished.
    assert new_context.node_uuid == "5824604b-d9b6-429a-b442-153c091756fe"
    refute is_nil(new_context.completed_at)
  end

  test "Flag is disabled for re-response feature",
       %{
         conn: conn,
         message_params: message_params
       } = attrs do
    FunWithFlags.disable(:is_interactive_re_response_enabled,
      for_actor: %{organization_id: attrs.organization_id}
    )

    # Refer int_msg_re_response.json
    # sending RCB as the response to the interactive template
    message_params =
      put_in(message_params, ["payload", "payload"], %{
        "id" => "62ff6da6-00f2-400d-ae43-253470d1a6be",
        "reply" => "RCB 1",
        "title" => "RCB"
      })

    conn2 = conn
    conn = post(conn, "/gupshup", message_params)
    assert conn.halted
    bsp_message_id = get_in(message_params, ["payload", "id"])

    {:ok, message} =
      Repo.fetch_by(Message, %{
        bsp_message_id: bsp_message_id,
        organization_id: conn.assigns[:organization_id]
      })

    assert message.bsp_status == :delivered

    flow =
      Flow.get_loaded_flow(attrs.organization_id, "published", %{
        uuid: "0633e385-0625-4432-98f7-e780a73944aa"
      })

    contact = Fixtures.contact_fixture()
    {:ok, flow_context, _} = FlowContext.init_context(flow, contact, "published")
    state = ConsumerFlow.load_state(Fixtures.get_org_id())
    assert is_tuple(ConsumerFlow.continue_current_context(flow_context, message, "body", state))

    new_context =
      Repo.get_by(FlowContext, contact_id: contact.id, flow_id: flow.id)

    # check the int_msg_re_response.json for more info. The message we send via webhook has reply "RCB 1"
    # according to it flow continues after continue_current_context and reach the next wait for response
    # which is awaiting response for "what u think, who will win" (which is a normal send_msg node).
    assert new_context.node_uuid == "f54b0868-8fb0-42fd-a9fc-8e15274bcea9"

    # But we again send response from the first interactive msg
    message_params =
      put_in(message_params, ["payload", "payload"], %{
        "id" => "62ff6da6-00f2-400d-ae43-253470d1a6be",
        "reply" => "KKR 1",
        "title" => "KKR"
      })

    conn2 = post(conn2, "/gupshup", message_params)
    assert conn2.halted
    bsp_message_id = get_in(message_params, ["payload", "id"])

    {:ok, message} =
      Repo.fetch_by(Message, %{
        bsp_message_id: bsp_message_id,
        organization_id: attrs.organization_id
      })

    assert message.bsp_status == :delivered

    assert is_tuple(ConsumerFlow.continue_current_context(new_context, message, "body", state))

    new_context =
      Repo.get_by(FlowContext, contact_id: contact.id, flow_id: flow.id)

    # Since the flag is disabled re-response didnt work and we reach end of the flow and
    # flow is completed
    refute new_context.node_uuid == "f54b0868-8fb0-42fd-a9fc-8e15274bcea9"

    refute is_nil(new_context.completed_at)

    FunWithFlags.disable(:is_interactive_re_response_enabled,
      for_actor: %{organization_id: attrs.organization_id}
    )
  end

  test "handles whatsapp form response correctly and includes and whatsapp response in the results map",
       %{
         conn: conn
       } = attrs do
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
      WhatsappForms.create_whatsapp_form(%{
        name: "Customer Feedback Form",
        meta_flow_id: "1787478395302778",
        form_json: %{
          "screens" => []
        },
        categories: ["other"],
        description: "A form to collect customer feedback",
        organization_id: conn.assigns[:organization_id]
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
                    "wa_id" => "9876543210_1"
                  }
                ],
                "messages" => [
                  %{
                    "context" => %{
                      "from" => "9876543210_1",
                      "gs_id" => "0e74fb92-eb8a-415a-bccd-42ee768665e0",
                      "id" => "031AGDymvDNTGOEfndITwW",
                      "meta_msg_id" =>
                        "wamid.HBgMOTE5NDI1MDEwNDQ5FQIAERgSNzY4MjM3OEU5RDBFQUY1MDNFAA=="
                    },
                    "from" => "9876543210_1",
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

    conn2 = post(conn, "/gupshup/message/whatsapp_form_response", payload)
    assert conn2.halted

    # Fetch the contact by phone
    contact =
      Repo.get_by(Contact, phone: "9876543210_1")

    # Fetch the created WhatsAppFormResponse from DB using contact.id
    form_response =
      Repo.one(
        from wfr in WhatsappFormResponse,
          where: wfr.contact_id == ^contact.id
      )

    assert form_response != nil
    assert form_response.raw_response["screen_0_Choose_one_0"] == "0_Yes"
    assert form_response.raw_response["screen_1_Customer_service_2"] == "0_Excellent"

    message =
      Repo.one(
        from m in Message,
          where:
            m.bsp_message_id == "wamid.HBgMOTE5NDI1MDEwNDQ5FQIAEhgUM0E3MzZCRDU0NTNCRTIxQUFFMzkA",
          preload: [:whatsapp_form_response]
      )

    assert message != nil
    assert message.type == :whatsapp_form_response

    flow =
      Flow.get_loaded_flow(attrs.organization_id, "published", %{
        uuid: "0633e385-0625-4432-98f7-e780a73944aa"
      })

    contact = Fixtures.contact_fixture()
    {:ok, flow_context, _} = FlowContext.init_context(flow, contact, "published")
    state = ConsumerFlow.load_state(Fixtures.get_org_id())
    assert is_tuple(ConsumerFlow.continue_current_context(flow_context, message, "body", state))

    new_context =
      Repo.get_by(FlowContext, contact_id: contact.id, flow_id: flow.id)

    assert new_context.results["result_1"]["screen_0_Choose_one_0"] == "0_Yes"
    assert new_context.results["result_1"]["screen_1_Customer_service_2"] == "0_Excellent"
  end
end
