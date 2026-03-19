defmodule GlificWeb.Flows.FlowResumeControllerTest do
  use GlificWeb.ConnCase
  use Publicist
  import Mock

  alias Glific.{
    Fixtures,
    Flows.Flow,
    Flows.FlowContext,
    Seeds.SeedsDev
  }

  alias GlificWeb.Flows.FlowResumeController

  setup do
    SeedsDev.seed_organizations()
    :ok
  end

  @ai_response "Glific is an open-source, two-way messaging platform designed for nonprofits to scale their outreach via WhatsApp. It helps organizations automate conversations, manage contacts, and measure impact, all in one centralized tool"

  describe "flow_resume_routes" do
    test "resumes an existing flow on receiving webhook event with success response", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      FunWithFlags.enable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )

      contact = Fixtures.contact_fixture()
      webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})

      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      flow =
        Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})

      [node | _tail] = flow.nodes

      signature_payload = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => contact.id,
        "timestamp" => timestamp
      }

      signature =
        Glific.signature(
          organization_id,
          Jason.encode!(signature_payload),
          signature_payload["timestamp"]
        )

      params = %{
        "data" => %{
          "callback" =>
            "https://api.glific.glific.com/webhook/flow_resume?organization_id=1&flow_id=16&contact_id=16&timestamp=1753377554424136&signature=97075c37cbcd0b97dc7a18d754656770d0613d1869f0ed500c041c7e01c20d2f",
          "chunks" => [],
          "contact_id" => contact.id,
          "diagnostics" => %{
            "input_tokens" => 27,
            "model" => "gpt-4o-2024-08-06",
            "output_tokens" => 343,
            "total_tokens" => 370
          },
          "endpoint" => "http://0.0.0.0:8000/api/v1/responses",
          "flow_id" => flow.id,
          "message" => @ai_response,
          "organization_id" => organization_id,
          "response_id" => "resp_68826b142198819881bce999ccd87a750d0635d313bf2c6f",
          "signature" => signature,
          "status" => "success",
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "filesearch"
        },
        "success" => true
      }

      wait_time = 60

      {:ok, _context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          wakeup_at: DateTime.add(DateTime.utc_now(), wait_time),
          is_await_result: true,
          node_uuid: node.uuid
        })

      conn =
        conn
        |> post("/webhook/flow_resume", params)

      assert json_response(conn, 200) == ""

      # once a response is received the flow moves to next node i.e. send the message which is @results.response.message

      [message | _messages] =
        Glific.Messages.list_messages(%{
          filter: %{contact_id: contact.id},
          opts: %{limit: 1, order: :desc}
        })

      # Checking the latest message, should be same as the one received at the endpoint
      assert message.body == @ai_response
    end

    test "resumes an existing flow on receiving webhook event with failure response", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      FunWithFlags.enable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )

      contact = Fixtures.contact_fixture()
      webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})

      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      flow =
        Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})

      [node | _tail] = flow.nodes

      signature_payload = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => contact.id,
        "timestamp" => timestamp
      }

      signature =
        Glific.signature(
          organization_id,
          Jason.encode!(signature_payload),
          signature_payload["timestamp"]
        )

      params = %{
        "data" => %{
          "callback" =>
            "https://api.glific.glific.com/webhook/flow_resume?organization_id=1&flow_id=16&contact_id=16&timestamp=1753377554424136&signature=97075c37cbcd0b97dc7a18d754656770d0613d1869f0ed500c041c7e01c20d2f",
          "contact_id" => contact.id,
          "endpoint" => "http://0.0.0.0:8000/api/v1/responses",
          "flow_id" => flow.id,
          "organization_id" => organization_id,
          "signature" => signature,
          "status" => "failure",
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "filesearch"
        },
        "success" => false
      }

      wait_time = 60

      {:ok, _context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          wakeup_at: DateTime.add(DateTime.utc_now(), wait_time),
          is_await_result: true,
          node_uuid: node.uuid
        })

      conn =
        conn
        |> post("/webhook/flow_resume", params)

      assert json_response(conn, 200) == ""

      # once a response is received the flow moves to next node i.e. send the message which is @results.response.message
      [message | _messages] =
        Glific.Messages.list_messages(%{
          filter: %{contact_id: contact.id},
          opts: %{limit: 1, order: :desc}
        })

      # Checking the latest message, should be failure because in the flow
      # the failed category's next send msg node has failure as body
      assert message.body == "failure"
    end

    test "resumes an existing flow on receiving unified API callback format", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      FunWithFlags.enable(:is_kaapi_enabled,
        for_actor: %{organization_id: organization_id}
      )

      contact = Fixtures.contact_fixture()
      webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})

      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      flow =
        Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})

      [node | _tail] = flow.nodes

      signature_payload = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => contact.id,
        "timestamp" => timestamp
      }

      signature =
        Glific.signature(
          organization_id,
          Jason.encode!(signature_payload),
          signature_payload["timestamp"]
        )

      params = %{
        "data" => %{
          "response" => %{
            "conversation_id" => "conv_abc123",
            "model" => "gpt-4o-2024-08-06",
            "output" => %{
              "content" => %{
                "format" => "text",
                "value" => @ai_response
              },
              "type" => "text"
            },
            "provider" => "openai-native",
            "provider_response_id" => "resp_xyz789"
          },
          "usage" => %{
            "input_tokens" => 22,
            "output_tokens" => 45,
            "total_tokens" => 67
          }
        },
        "metadata" => %{
          "organization_id" => organization_id,
          "flow_id" => flow.id,
          "contact_id" => contact.id,
          "signature" => signature,
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "filesearch"
        },
        "success" => true
      }

      wait_time = 60

      {:ok, _context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          wakeup_at: DateTime.add(DateTime.utc_now(), wait_time),
          is_await_result: true,
          node_uuid: node.uuid
        })

      conn =
        conn
        |> post("/webhook/flow_resume", params)

      assert json_response(conn, 200) == ""

      [message | _messages] =
        Glific.Messages.list_messages(%{
          filter: %{contact_id: contact.id},
          opts: %{limit: 1, order: :desc}
        })

      # The message should contain the AI response extracted from the nested unified format
      assert message.body == @ai_response
    end

    test "resumes flow on Kaapi STT callback with transcribed text", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      contact = Fixtures.contact_fixture()
      webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
      [node | _tail] = flow.nodes

      signature_payload = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => contact.id,
        "timestamp" => timestamp
      }

      signature =
        Glific.signature(
          organization_id,
          Jason.encode!(signature_payload),
          timestamp
        )

      params = %{
        "data" => %{
          "response" => %{
            "conversation_id" => "conv_stt_123",
            "output" => %{
              "type" => "text",
              "content" => %{"value" => "Hello this is the transcribed text"}
            }
          }
        },
        "metadata" => %{
          "organization_id" => organization_id,
          "flow_id" => flow.id,
          "contact_id" => contact.id,
          "signature" => signature,
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "response"
        },
        "success" => true
      }

      {:ok, _context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          wakeup_at: DateTime.add(DateTime.utc_now(), 60),
          is_await_result: true,
          node_uuid: node.uuid
        })

      conn = post(conn, "/webhook/flow_resume", params)
      assert json_response(conn, 200) == ""
    end

    test "resumes flow on Kaapi TTS callback with audio output type", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      contact = Fixtures.contact_fixture()
      webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
      [node | _tail] = flow.nodes

      signature_payload = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => contact.id,
        "timestamp" => timestamp
      }

      signature =
        Glific.signature(
          organization_id,
          Jason.encode!(signature_payload),
          timestamp
        )

      # Small valid base64 OGG-like content for testing upload path
      fake_audio_b64 = Base.encode64("fake_ogg_audio_bytes")

      params = %{
        "data" => %{
          "response" => %{
            "conversation_id" => "conv_tts_456",
            "output" => %{
              "type" => "audio",
              "content" => %{"value" => fake_audio_b64}
            }
          }
        },
        "metadata" => %{
          "organization_id" => organization_id,
          "flow_id" => flow.id,
          "contact_id" => contact.id,
          "signature" => signature,
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "response"
        },
        "success" => true
      }

      {:ok, _context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          wakeup_at: DateTime.add(DateTime.utc_now(), 60),
          is_await_result: true,
          node_uuid: node.uuid
        })

      with_mock Glific.GCS.GcsWorker,
        upload_media: fn _file, _remote, _org ->
          {:ok, %{url: "https://storage.googleapis.com/bucket/Kaapi/outbound/test.ogg"}}
        end do
        conn = post(conn, "/webhook/flow_resume", params)
        assert json_response(conn, 200) == ""
      end
    end

    test "resumes flow with Failure on STT/TTS callback with success: false", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      contact = Fixtures.contact_fixture()
      webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
      [node | _tail] = flow.nodes

      signature_payload = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => contact.id,
        "timestamp" => timestamp
      }

      signature =
        Glific.signature(
          organization_id,
          Jason.encode!(signature_payload),
          timestamp
        )

      params = %{
        "data" => %{},
        "metadata" => %{
          "organization_id" => organization_id,
          "flow_id" => flow.id,
          "contact_id" => contact.id,
          "signature" => signature,
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "response"
        },
        "success" => false,
        "error_type" => "transcription_failed",
        "reason" => "Could not transcribe audio"
      }

      {:ok, _context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          wakeup_at: DateTime.add(DateTime.utc_now(), 60),
          is_await_result: true,
          node_uuid: node.uuid
        })

      conn = post(conn, "/webhook/flow_resume", params)
      assert json_response(conn, 200) == ""

      [message | _] =
        Glific.Messages.list_messages(%{
          filter: %{contact_id: contact.id},
          opts: %{limit: 1, order: :desc}
        })

      assert message.body == "failure"
    end

    test "returns 200 and ignores request when signature is invalid", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      contact = Fixtures.contact_fixture()
      webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})

      params = %{
        "data" => %{
          "response" => %{
            "output" => %{"type" => "text", "content" => %{"value" => "hello"}}
          }
        },
        "metadata" => %{
          "organization_id" => organization_id,
          "flow_id" => flow.id,
          "contact_id" => contact.id,
          "signature" => "invalid_signature",
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "response"
        },
        "success" => true
      }

      conn = post(conn, "/webhook/flow_resume", params)
      assert json_response(conn, 200) == ""
    end

    test "resumes flow with No Response when success: true but no webhook_log_id", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      contact = Fixtures.contact_fixture()
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
      [node | _tail] = flow.nodes

      signature_payload = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => contact.id,
        "timestamp" => timestamp
      }

      signature =
        Glific.signature(
          organization_id,
          Jason.encode!(signature_payload),
          timestamp
        )

      params = %{
        "data" => %{
          "response" => %{
            "output" => %{"type" => "text", "content" => %{"value" => "hello"}},
            "conversation_id" => "conv_no_log"
          }
        },
        "metadata" => %{
          "organization_id" => organization_id,
          "flow_id" => flow.id,
          "contact_id" => contact.id,
          "signature" => signature,
          "timestamp" => timestamp,
          "result_name" => "response"
        },
        "success" => true
      }

      {:ok, _context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          wakeup_at: DateTime.add(DateTime.utc_now(), 60),
          is_await_result: true,
          node_uuid: node.uuid
        })

      conn = post(conn, "/webhook/flow_resume", params)
      assert json_response(conn, 200) == ""
    end

    test "voice_flow_resume resumes the flow after voice post-processing", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      contact = Fixtures.contact_fixture()
      webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
      [node | _tail] = flow.nodes

      signature_payload = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => contact.id,
        "timestamp" => timestamp
      }

      signature =
        Glific.signature(
          organization_id,
          Jason.encode!(signature_payload),
          timestamp
        )

      params = %{
        "data" => %{
          "response" => %{
            "conversation_id" => "conv_voice_123",
            "output" => %{"type" => "text", "content" => %{"value" => "Voice answer"}}
          }
        },
        "metadata" => %{
          "organization_id" => organization_id,
          "flow_id" => flow.id,
          "contact_id" => contact.id,
          "signature" => signature,
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "result",
          "voice_post_process" => %{
            "source_language" => "english",
            "target_language" => "english",
            "speech_engine" => ""
          }
        },
        "success" => true
      }

      {:ok, _context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          wakeup_at: DateTime.add(DateTime.utc_now(), 60),
          is_await_result: true,
          node_uuid: node.uuid
        })

      conn = post(conn, "/kaapi/voice_flow_resume", params)
      assert json_response(conn, 200) == ""
    end

    test "voice_flow_resume returns 200 for unexpected callback format", %{
      conn: conn
    } do
      conn = post(conn, "/kaapi/voice_flow_resume", %{"unexpected" => "format"})
      assert json_response(conn, 200) == ""
    end

    test "voice_flow_resume returns 200 for invalid signature", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      contact = Fixtures.contact_fixture()
      webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})

      params = %{
        "data" => %{
          "response" => %{
            "conversation_id" => "conv_voice_invalid",
            "output" => %{"type" => "text", "content" => %{"value" => "should not appear"}}
          }
        },
        "metadata" => %{
          "organization_id" => organization_id,
          "flow_id" => flow.id,
          "contact_id" => contact.id,
          "signature" => "invalid_signature",
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "result"
        },
        "success" => true
      }

      conn = post(conn, "/kaapi/voice_flow_resume", params)
      assert json_response(conn, 200) == ""
    end

    test "do_voice_flow_resume resumes flow with voice response on success", %{
      conn: %{assigns: %{organization_id: organization_id}} = _conn
    } do
      contact = Fixtures.contact_fixture()
      webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
      [node | _tail] = flow.nodes

      signature_payload = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => contact.id,
        "timestamp" => timestamp
      }

      signature =
        Glific.signature(organization_id, Jason.encode!(signature_payload), timestamp)

      response = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => contact.id,
        "signature" => signature,
        "timestamp" => timestamp,
        "webhook_log_id" => webhook_log.id,
        "result_name" => "result",
        "message" => "Voice answer"
      }

      {:ok, _context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          wakeup_at: DateTime.add(DateTime.utc_now(), 60),
          is_await_result: true,
          node_uuid: node.uuid
        })

      assert :ok =
               FlowResumeController.do_voice_flow_resume(
                 organization_id,
                 %{"success" => false},
                 response
               )
    end

    test "returns 200 when TTS audio upload fails (bad base64)", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
      contact = Fixtures.contact_fixture()
      webhook_log = Fixtures.webhook_log_fixture(%{organization_id: organization_id})
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)

      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
      [node | _tail] = flow.nodes

      signature_payload = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => contact.id,
        "timestamp" => timestamp
      }

      signature =
        Glific.signature(
          organization_id,
          Jason.encode!(signature_payload),
          timestamp
        )

      params = %{
        "data" => %{
          "response" => %{
            "conversation_id" => "conv_tts_bad",
            "output" => %{
              "type" => "audio",
              "content" => %{"value" => "!!!not_valid_base64!!!"}
            }
          }
        },
        "metadata" => %{
          "organization_id" => organization_id,
          "flow_id" => flow.id,
          "contact_id" => contact.id,
          "signature" => signature,
          "timestamp" => timestamp,
          "webhook_log_id" => webhook_log.id,
          "result_name" => "response"
        },
        "success" => true
      }

      {:ok, _context} =
        FlowContext.create_flow_context(%{
          contact_id: contact.id,
          flow_id: flow.id,
          flow_uuid: flow.uuid,
          uuid_map: %{},
          organization_id: organization_id,
          wakeup_at: DateTime.add(DateTime.utc_now(), 60),
          is_await_result: true,
          node_uuid: node.uuid
        })

      conn = post(conn, "/webhook/flow_resume", params)
      assert json_response(conn, 200) == ""
    end
  end
end
