defmodule Glific.Flows.Webhooks.CreateCertificateTest do
  use Glific.DataCase, async: false
  use Oban.Pro.Testing, repo: Glific.Repo

  import Glific.WebhookTestHelpers
  import Mock

  alias Glific.{
    Certificates.CertificateTemplate,
    Fixtures,
    Flows.Action,
    Flows.Flow,
    Flows.FlowContext,
    Flows.Webhook,
    Flows.WebhookLog,
    Flows.Webhooks.Dispatcher,
    Partners,
    Repo,
    Seeds.SeedsDev
  }

  @mock_presentation_id "copied_presentation123"
  @mock_copied_slide %{"id" => @mock_presentation_id}
  @mock_thumbnail %{"contentUrl" => "image_url"}

  setup do
    default_provider = SeedsDev.seed_providers()
    SeedsDev.seed_organizations(default_provider)

    {:ok, _credential} =
      Partners.create_credential(%{
        shortcode: "google_cloud_storage",
        secrets: %{
          "bucket" => "mock-bucket",
          "service_account" =>
            Jason.encode!(%{
              project_id: "test",
              private_key_id: "key",
              client_email: "test@test.com",
              private_key: "TEST PRIVATE KEY"
            })
        },
        is_active: true,
        organization_id: 1
      })

    {:ok, _credential} =
      Partners.create_credential(%{
        shortcode: "google_slides",
        secrets: %{
          "service_account" =>
            Jason.encode!(%{
              project_id: "test",
              private_key_id: "key",
              client_email: "test@test.com",
              private_key: "TEST PRIVATE KEY"
            })
        },
        is_active: true,
        organization_id: 1
      })

    :ok
  end

  # Build a FlowContext linked to the real call_and_wait flow so that
  # FlowContext.wakeup_one/2 can load the flow and advance it after the
  # webhook job completes. Returns {context, flow_attrs, contact}.
  defp build_context(attrs) do
    contact = Fixtures.contact_fixture(attrs)
    flow = Flow.get_loaded_flow(attrs.organization_id, "published", %{keyword: "call_and_wait"})
    [node | _] = flow.nodes

    flow_attrs = %{
      flow_id: flow.id,
      contact_id: contact.id,
      organization_id: attrs.organization_id
    }

    {:ok, context} =
      FlowContext.create_flow_context(%{
        contact_id: contact.id,
        flow_id: flow.id,
        flow_uuid: flow.uuid,
        organization_id: attrs.organization_id,
        node_uuid: node.uuid,
        is_await_result: true
      })

    {Repo.preload(context, [:contact, :flow]), flow_attrs, contact}
  end

  defp certificate_template_attrs do
    %{
      label: "test",
      type: :slides,
      url: "https://docs.google.com/presentation/d/#{@mock_presentation_id}/edit#slide=id.g2",
      organization_id: 1
    }
  end

  defp mock_all_google_apis_success do
    Tesla.Mock.mock(fn
      %Tesla.Env{
        method: :post,
        url: "https://storage.googleapis.com/upload/storage/v1/b/mock-bucket/o",
        query: [uploadType: "multipart"]
      } ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body:
             Jason.encode!(%{
               "name" => "uploads/certificate/#{@mock_presentation_id}/123.png",
               "mediaLink" =>
                 "https://storage.googleapis.com/mock-bucket/uploads/certificate/#{@mock_presentation_id}/123.png",
               "selfLink" =>
                 "https://storage.googleapis.com/mock-bucket/uploads/certificate/#{@mock_presentation_id}/123.png"
             })
         }}

      %{
        method: :get,
        url:
          "https://storage.googleapis.com/mock-bucket/uploads/certificate/#{@mock_presentation_id}/123.png"
      } ->
        {:ok, %Tesla.Env{status: 200, body: "<<binary image data>>"}}

      %{
        method: :post,
        url:
          "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/copy?supportsAllDrives=true"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(@mock_copied_slide)}}

      %{
        method: :post,
        url: "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/permissions"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}

      %{
        method: :post,
        url: "https://slides.googleapis.com/v1/presentations/#{@mock_presentation_id}:batchUpdate"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}

      %{
        method: :get,
        url:
          "https://slides.googleapis.com/v1/presentations/#{@mock_presentation_id}/pages/g2/thumbnail"
      } ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(@mock_thumbnail)}}

      %{
        method: :get,
        url:
          "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}?supportsAllDrives=true"
      } ->
        {:ok, %Tesla.Env{status: 200, body: ""}}

      %{method: :get, url: "image_url"} ->
        {:ok, %Tesla.Env{status: 200, body: "<<binary image data>>"}}
    end)
  end

  describe "create_certificate" do
    test "happy path: enqueues on custom_certificate queue, logs success, and resumes flow",
         attrs do
      with_mock(Goth.Token, [],
        fetch: fn _url ->
          {:ok, %{token: "mock_access_token", expires: System.system_time(:second) + 120}}
        end
      ) do
        mock_all_google_apis_success()

        {:ok, certificate} =
          CertificateTemplate.create_certificate_template(certificate_template_attrs())

        {context, flow_attrs, contact} = build_context(attrs)

        action = %Action{
          method: "FUNCTION",
          url: "create_certificate",
          headers: %{},
          body:
            Jason.encode!(%{
              certificate_id: certificate.id,
              contact: %{"id" => contact.id, "name" => "Test User"},
              replace_texts: %{}
            }),
          result_name: "filesearch"
        }

        assert Webhook.execute(action, context) == nil

        [job] = all_enqueued(worker: Webhook, prefix: "global")
        assert job.queue == "custom_certificate"

        Oban.drain_queue(queue: :custom_certificate)

        # WebhookLog assertions — verify the webhook itself succeeded
        log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
        assert log.status == "Success"
        assert log.response_json["success"] == true
        assert log.response_json["certificate_url"] != nil

        # Flow execution assertion — verify the flow resumed on the success branch.
        # The call_and_wait success node sends "@results.filesearch.message"; since
        # the create_certificate result has no "message" key, the template expression
        # is rendered as-is, proving the flow engine advanced past the webhook node.
        message = await_flow_message(context.contact_id, "@results.filesearch.message")
        assert message.body == "@results.filesearch.message"
      end
    end

    test "failure: Google Slides API error logs an error and flow still resumes", attrs do
      with_mock(Goth.Token, [],
        fetch: fn _url ->
          {:ok, %{token: "mock_access_token", expires: System.system_time(:second) + 120}}
        end
      ) do
        Tesla.Mock.mock(fn
          %{
            method: :get,
            url:
              "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}?supportsAllDrives=true"
          } ->
            {:ok, %Tesla.Env{status: 200, body: ""}}

          %{
            method: :post,
            url:
              "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/copy?supportsAllDrives=true"
          } ->
            {:ok, %Tesla.Env{status: 400, body: Jason.encode!(@mock_copied_slide)}}
        end)

        {:ok, certificate} =
          CertificateTemplate.create_certificate_template(certificate_template_attrs())

        {context, flow_attrs, contact} = build_context(attrs)

        action = %Action{
          method: "FUNCTION",
          url: "create_certificate",
          headers: %{},
          body:
            Jason.encode!(%{
              certificate_id: certificate.id,
              contact: %{"id" => contact.id, "name" => "Test User"},
              replace_texts: %{}
            }),
          result_name: "filesearch"
        }

        assert Webhook.execute(action, context) == nil

        Oban.drain_queue(queue: :custom_certificate)

        # WebhookLog assertions — verify the webhook recorded the failure
        log = List.first(WebhookLog.list_webhook_logs(%{filter: flow_attrs}))
        assert log != nil
        assert log.error != nil

        # Flow execution assertion — a generation failure returns a typed
        # {:error, :unknown, reason}, so the flow routes to the Failure branch.
        message = await_flow_message(context.contact_id, "failure")
        assert message.body == "failure"
      end
    end
  end

  defp cert_fields(certificate_id, contact_id) do
    %{
      "certificate_id" => certificate_id,
      "contact" => %{"id" => contact_id},
      "organization_id" => 1,
      "replace_texts" => %{"{1}" => "John Doe", "{2}" => "March 5, 2025"}
    }
  end

  defp with_goth(fun) do
    with_mock(Goth.Token, [],
      fetch: fn _url ->
        {:ok, %{token: "mock_access_token", expires: System.system_time(:second) + 120}}
      end
    ) do
      fun.()
    end
  end

  # Dispatch-level tests: exercise call/2's Google Slides/GCS failure branches and validation
  # directly via the Dispatcher (the e2e tests above cover happy + a single Google failure).
  describe "create_certificate dispatch" do
    test "returns failure when the thumbnail download fails" do
      Tesla.Mock.mock(fn
        %Tesla.Env{
          method: :post,
          url: "https://storage.googleapis.com/upload/storage/v1/b/mock-bucket/o",
          query: [uploadType: "multipart"]
        } ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: Jason.encode!(%{"name" => "n", "mediaLink" => "m", "selfLink" => "s"})
           }}

        %{
          method: :post,
          url:
            "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/copy?supportsAllDrives=true"
        } ->
          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(@mock_copied_slide)}}

        %{
          method: :post,
          url: "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/permissions"
        } ->
          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}

        %{
          method: :post,
          url:
            "https://slides.googleapis.com/v1/presentations/#{@mock_presentation_id}:batchUpdate"
        } ->
          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}

        %{
          method: :get,
          url:
            "https://slides.googleapis.com/v1/presentations/#{@mock_presentation_id}/pages/g2/thumbnail"
        } ->
          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(@mock_thumbnail)}}

        %{
          method: :get,
          url:
            "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}?supportsAllDrives=true"
        } ->
          {:ok, %Tesla.Env{status: 200, body: ""}}

        %{method: :get, url: "image_url"} ->
          {:ok, %Tesla.Env{status: 400, body: "<<binary image data>>"}}
      end)

      with_goth(fn ->
        {:ok, certificate} =
          CertificateTemplate.create_certificate_template(certificate_template_attrs())

        contact = Fixtures.contact_fixture()

        result =
          Dispatcher.dispatch("create_certificate", cert_fields(certificate.id, contact.id))

        assert {:error, _type, "Failed to download thumbnail url"} = result
      end)
    end

    test "returns failure on a GCS upload failure" do
      Tesla.Mock.mock(fn
        %Tesla.Env{
          method: :post,
          url: "https://storage.googleapis.com/upload/storage/v1/b/mock-bucket/o",
          query: [uploadType: "multipart"]
        } ->
          {:ok,
           %Tesla.Env{
             status: 400,
             body: Jason.encode!(%{"error" => %{"errors" => [%{"reason" => "boom"}]}})
           }}

        %{
          method: :post,
          url:
            "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/copy?supportsAllDrives=true"
        } ->
          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(@mock_copied_slide)}}

        %{
          method: :post,
          url: "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/permissions"
        } ->
          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}

        %{
          method: :post,
          url:
            "https://slides.googleapis.com/v1/presentations/#{@mock_presentation_id}:batchUpdate"
        } ->
          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{"success" => true})}}

        %{
          method: :get,
          url:
            "https://slides.googleapis.com/v1/presentations/#{@mock_presentation_id}/pages/g2/thumbnail"
        } ->
          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(@mock_thumbnail)}}

        %{
          method: :get,
          url:
            "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}?supportsAllDrives=true"
        } ->
          {:ok, %Tesla.Env{status: 200, body: ""}}

        %{method: :get, url: "image_url"} ->
          {:ok, %Tesla.Env{status: 200, body: "<<binary image data>>"}}
      end)

      with_goth(fn ->
        {:ok, certificate} =
          CertificateTemplate.create_certificate_template(certificate_template_attrs())

        contact = Fixtures.contact_fixture()

        # A generation failure now returns a typed error → dispatcher yields the reason string.
        assert {:error, _type, reason} =
                 Dispatcher.dispatch(
                   "create_certificate",
                   cert_fields(certificate.id, contact.id)
                 )

        assert is_binary(reason)
      end)
    end

    test "returns failure when slide copy fails" do
      Tesla.Mock.mock(fn
        %{
          method: :get,
          url:
            "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}?supportsAllDrives=true"
        } ->
          {:ok, %Tesla.Env{status: 200, body: ""}}

        %{
          method: :post,
          url:
            "https://www.googleapis.com/drive/v3/files/#{@mock_presentation_id}/copy?supportsAllDrives=true"
        } ->
          {:ok, %Tesla.Env{status: 400, body: Jason.encode!(@mock_copied_slide)}}
      end)

      with_goth(fn ->
        {:ok, certificate} =
          CertificateTemplate.create_certificate_template(certificate_template_attrs())

        contact = Fixtures.contact_fixture()

        assert {:error, _type, reason} =
                 Dispatcher.dispatch(
                   "create_certificate",
                   cert_fields(certificate.id, contact.id)
                 )

        assert reason =~ "Failed to copy slide. Status: 400"
      end)
    end

    test "returns an error string when the certificate template doesn't exist" do
      assert {:error, _type, "Certificate template not found for ID: 111"} =
               Dispatcher.dispatch("create_certificate", cert_fields(111, "123"))
    end

    test "returns a validation error string when required fields are missing/invalid" do
      assert {:error, _type, error} = Dispatcher.dispatch("create_certificate", %{})
      assert is_binary(error)
      assert String.split(error, "is required") |> length() == 5

      assert {:error, _type, "replace_texts is invalid"} =
               Dispatcher.dispatch("create_certificate", %{
                 "certificate_id" => "1",
                 "organization_id" => 1,
                 "contact" => %{"id" => "123"},
                 "replace_texts" => "John Doe"
               })

      assert {:error, _type, "contact is required"} =
               Dispatcher.dispatch("create_certificate", %{
                 "certificate_id" => "1",
                 "organization_id" => 1,
                 "replace_texts" => %{"{1}" => "John Doe"}
               })
    end

    test "returns a validation error (no crash) on non-numeric certificate_id" do
      result =
        Dispatcher.dispatch("create_certificate", %{
          "certificate_id" => "not-a-number",
          "organization_id" => 1,
          "contact" => %{"id" => "123"},
          "replace_texts" => %{"{1}" => "John Doe"}
        })

      assert {:error, _type, reason} = result
      assert reason =~ "certificate_id must be a valid integer"
    end
  end
end
