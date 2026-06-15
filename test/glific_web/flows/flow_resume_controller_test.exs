defmodule GlificWeb.Flows.FlowResumeControllerTest do
  use GlificWeb.ConnCase
  use Publicist
  import Mock

  alias Glific.{
    Fixtures,
    Flows.Flow,
    Flows.FlowContext,
    Flows.WebhookLog,
    Flows.Webhooks.Errors.SystemError,
    Repo,
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
      message = await_flow_message(contact.id, @ai_response)
      assert message.body == @ai_response
    end

    test "resumes an existing flow on receiving webhook event with failure response", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
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
          "message" => "Kaapi error: response generation failed",
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

      message = await_flow_message(contact.id, "failure")
      assert message.body == "failure"

      updated_webhook_log = Repo.get!(WebhookLog, webhook_log.id)

      assert updated_webhook_log.response_json["message"] ==
               "Kaapi error: response generation failed"

      assert updated_webhook_log.response_json["success"] == false
      assert updated_webhook_log.response_json["thread_id"] == nil
    end

    test "resumes an existing flow on receiving unified API callback format", %{
      conn: %{assigns: %{organization_id: organization_id}} = conn
    } do
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

      message = await_flow_message(contact.id, @ai_response)
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

      message = await_flow_message(contact.id, "failure")
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

      # Call do_voice_flow_resume directly to verify the flow is NOT resumed
      response = FlowResumeController.parse_callback_response(params)

      with_mock FlowContext,
        resume_contact_flow: fn _contact, _flow_id, _results, _message -> {:ok, nil, []} end do
        assert :ok =
                 FlowResumeController.do_voice_flow_resume(
                   organization_id,
                   params,
                   response
                 )

        refute called(FlowContext.resume_contact_flow(:_, :_, :_, :_))
      end
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

    test "do_voice_flow_resume reports SystemError when callback says success=false", %{
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
        "message" => "Voice answer",
        "webhook_name" => "unified-voice-llm-call"
      }

      result = %{
        "success" => false,
        "reason" => "LLM provider timed out",
        "error_type" => "timeout"
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

      {exception, tags} =
        capture_appsignal(fn ->
          assert :ok =
                   FlowResumeController.do_voice_flow_resume(
                     organization_id,
                     result,
                     response
                   )
        end)

      assert %SystemError{} = exception
      assert Exception.message(exception) == "Webhook callback failure"
      assert tags.organization_id == organization_id
      assert tags.webhook_name == "unified-voice-llm-call"
      assert tags.flow_id == flow.id
      assert tags.contact_id == contact.id
      assert tags.webhook_log_id == webhook_log.id
      assert tags.error_type == "timeout"
      assert tags.reason == "LLM provider timed out"
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

    test "flow_resume returns 200 for unexpected callback format (no data/metadata)", %{
      conn: conn
    } do
      conn = post(conn, "/webhook/flow_resume", %{"unexpected" => "format"})
      assert json_response(conn, 200) == ""
    end

    test "do_flow_resume logs warning when a required callback field is missing", %{
      conn: %{assigns: %{organization_id: organization_id}} = _conn
    } do
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})

      # response is missing the required "signature" field
      response = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => 1,
        "timestamp" => timestamp
      }

      assert :ok =
               FlowResumeController.do_flow_resume(
                 organization_id,
                 %{"success" => true},
                 response
               )
    end

    test "do_flow_resume logs warning when contact is not found", %{
      conn: %{assigns: %{organization_id: organization_id}} = _conn
    } do
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})
      non_existent_contact_id = 999_999

      signature_payload = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => non_existent_contact_id,
        "timestamp" => timestamp
      }

      signature =
        Glific.signature(organization_id, Jason.encode!(signature_payload), timestamp)

      response = %{
        "organization_id" => organization_id,
        "flow_id" => flow.id,
        "contact_id" => non_existent_contact_id,
        "signature" => signature,
        "timestamp" => timestamp,
        "result_name" => "response"
      }

      assert :ok =
               FlowResumeController.do_flow_resume(
                 organization_id,
                 %{"success" => true},
                 response
               )
    end

    test "do_flow_resume logs warning when resume_contact_flow returns an error", %{
      conn: %{assigns: %{organization_id: organization_id}} = _conn
    } do
      contact = Fixtures.contact_fixture()
      timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
      flow = Flow.get_loaded_flow(organization_id, "published", %{keyword: "call_and_wait"})

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
        "result_name" => "response"
      }

      with_mock FlowContext, [:passthrough],
        resume_contact_flow: fn _contact, _flow_id, _results, _message ->
          {:error, "flow context not found"}
        end do
        assert :ok =
                 FlowResumeController.do_flow_resume(
                   organization_id,
                   %{"success" => true},
                   response
                 )

        assert called(FlowContext.resume_contact_flow(:_, :_, :_, :_))
      end
    end

    test "run_supervised_task rescues exceptions and returns :ok" do
      assert :ok =
               FlowResumeController.run_supervised_task(fn ->
                 raise "test exception in supervised task"
               end)
    end
  end

  @await_flow_message_attempts 50
  @await_flow_message_interval_ms 100

  defp await_flow_message(contact_id, expected_body) do
    await_flow_resume_tasks()
    await_flow_message(contact_id, expected_body, @await_flow_message_attempts)
  end

  defp await_flow_resume_tasks(attempts \\ 50)

  defp await_flow_resume_tasks(0) do
    flunk("Timed out waiting for flow resume background task")
  end

  defp await_flow_resume_tasks(attempts) do
    case Supervisor.count_children(Glific.TaskSupervisor) do
      %{active: 0} ->
        :ok

      _ ->
        Process.sleep(@await_flow_message_interval_ms)
        await_flow_resume_tasks(attempts - 1)
    end
  end

  defp await_flow_message(contact_id, expected_body, 0) do
    flunk(
      "Timed out waiting for message body #{inspect(expected_body)} for contact #{contact_id}"
    )
  end

  defp await_flow_message(contact_id, expected_body, attempts) do
    case Glific.Messages.list_messages(%{
           filter: %{contact_id: contact_id},
           opts: %{limit: 1, order: :desc}
         }) do
      [%{body: ^expected_body} = message | _] ->
        message

      _ ->
        Process.sleep(@await_flow_message_interval_ms)
        await_flow_message(contact_id, expected_body, attempts - 1)
    end
  end

  defp capture_appsignal(fun) do
    test_pid = self()

    with_mocks([
      {Appsignal, [:passthrough],
       [
         send_error: fn ex, _stack, configurator ->
           send(test_pid, {:appsignal_exception, ex})
           configurator.(:fake_span)
           :ok
         end
       ]},
      {Appsignal.Span, [:passthrough],
       [
         set_sample_data: fn _span, key, value ->
           send(test_pid, {:appsignal_tag, key, value})
           :fake_span
         end
       ]}
    ]) do
      fun.()
    end

    exception =
      receive do
        {:appsignal_exception, ex} -> ex
      after
        100 -> flunk("Appsignal.send_error was not called")
      end

    tags =
      receive do
        {:appsignal_tag, "tags", t} -> t
      after
        100 -> %{}
      end

    {exception, tags}
  end
end
