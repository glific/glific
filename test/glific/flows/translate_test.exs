defmodule Glific.Flows.TranslateTest do
  use Glific.DataCase
  import Tesla.Mock

  alias Glific.{
    Flows,
    Flows.Flow,
    Flows.Translate.Export,
    Flows.Translate.Import,
    GoogleTranslate.Translate,
    Repo,
    Seeds.SeedsDev
  }

  setup do
    organization = SeedsDev.seed_organizations()
    SeedsDev.seed_contacts()
    SeedsDev.seed_interactives(organization)
    SeedsDev.seed_test_flows(organization)
    :ok
  end

  @help_flow_id 1

  test "ensure that export extracts the right nodes from the help flow", attrs do
    {result, _errors} =
      attrs.organization_id
      |> Flows.get_complete_flow(@help_flow_id)
      |> Export.export_localization()

    [_h1 | [_h2 | rows]] = result

    # check that each row is a 4 element list and is a translation or not
    Enum.each(
      rows,
      fn row ->
        assert length(row) == 5
        [type, uuid, src, dst, _node_uuid] = row
        assert type == "Action"
        assert String.length(uuid) == 36

        if uuid != "e319cd39-f764-4680-9199-4cb7da647166",
          do: assert(dst == "Hindi #{src} English")
      end
    )
  end

  test "ensure that import updates the localization structure", attrs do
    flow = Flows.get_complete_flow(attrs.organization_id, @help_flow_id)
    assert map_size(flow.definition["localization"]) == 1
    assert map_size(flow.definition["localization"]["hi"]) == 1
    {csv, _errors} = Export.export_localization(flow)
    Import.import_localization(csv, flow)

    flow = Flows.get_complete_flow(attrs.organization_id, @help_flow_id)

    assert map_size(flow.definition["localization"]) == 1
    assert map_size(flow.definition["localization"]["hi"]) == 6

    # we don't auto translate the default language
    assert flow.definition["localization"]["en"] == nil
  end

  test "ensure that import doesn't change the attachment url", attrs do
    {:ok, flow} = Repo.fetch_by(Flow, %{name: "Media flow"})
    flow_before_import = Flows.get_complete_flow(attrs.organization_id, flow.id)

    attachment_url_before =
      get_in(flow_before_import.definition, [
        "localization",
        "hi",
        "a970d5d9-2951-48dc-8c66-ee6833c4b21e"
      ])

    {csv, _errors} = Export.export_localization(flow_before_import)
    Import.import_localization(csv, flow_before_import)

    flow_after_import = Flows.get_complete_flow(attrs.organization_id, flow.id)

    attachment_url_after =
      get_in(flow_after_import.definition, [
        "localization",
        "hi",
        "a970d5d9-2951-48dc-8c66-ee6833c4b21e"
      ])

    assert attachment_url_before == attachment_url_after
  end

  test "export_localization/2 with add_translation false leaves the newly added translations blank",
       attrs do

    flow = Flows.get_complete_flow(attrs.organization_id, @help_flow_id)
    Flows.update_cached_flow(flow, "draft")
    flow = Flows.get_complete_flow(attrs.organization_id, @help_flow_id)

    {rows, errors} = Export.export_localization(flow, false)

    assert errors == []

    [_labels | [_keys | data_rows]] = rows

    Enum.each(data_rows, fn row ->
      [type, uuid, _src, _dst, _node_uuid] = row
      assert type == "Action"
      assert String.length(uuid) == 36
    end)

    assert Enum.any?(data_rows, fn [_type, _uuid, _src, dst, _node_uuid] -> dst == "" end)
  end

  test "translate/1 returns an error and does not import when a translation hard-fails", attrs do
    Application.put_env(:glific, :adaptors, translators: Glific.Flows.Translate.GoogleTranslate)

    on_exit(fn ->
      Application.put_env(:glific, :adaptors, translators: Glific.Flows.Translate.Simple)
    end)

    mock_global(fn _env ->
      %Tesla.Env{
        status: 403,
        body: %{
          "error" => %{
            "code" => 403,
            "status" => "PERMISSION_DENIED",
            "message" => "Requests to this API are blocked.",
            "details" => [%{"reason" => "API_KEY_SERVICE_BLOCKED"}]
          }
        }
      }
    end)

    flow = Flows.get_complete_flow(attrs.organization_id, @help_flow_id)
    Flows.update_cached_flow(flow, "draft")
    flow = Flows.get_complete_flow(attrs.organization_id, @help_flow_id)

    assert {:error, reason} = Export.translate(flow)
    assert reason =~ "Translation has failed"

    flow_after = Flows.get_complete_flow(attrs.organization_id, @help_flow_id)
    assert map_size(flow_after.definition["localization"]["hi"]) == 1
  end

  describe "Glific.GoogleTranslate.Translate.parse/3" do
    @languages %{"source" => "en", "target" => "hi"}

    test "returns translated text on a 200 response" do
      mock(fn _env ->
        %Tesla.Env{
          status: 200,
          body: %{
            "data" => %{
              "translations" => [%{"translatedText" => "नमस्ते दुनिया"}]
            }
          }
        }
      end)

      assert {:ok, "नमस्ते दुनिया"} = Translate.parse("api_key", "Hello World", @languages)
    end

    test "surfaces the HTTP status and Google error reason on a 403 API_KEY_SERVICE_BLOCKED response" do
      mock(fn _env ->
        %Tesla.Env{
          status: 403,
          body: %{
            "error" => %{
              "code" => 403,
              "status" => "PERMISSION_DENIED",
              "message" =>
                "Requests to this API translate method google.cloud.translate.v2.TranslateService.TranslateText are blocked.",
              "details" => [%{"reason" => "API_KEY_SERVICE_BLOCKED"}]
            }
          }
        }
      end)

      assert {:error, reason} = Translate.parse("bad_api_key", "Hello World", @languages)
      assert reason =~ "403"
      assert reason =~ "API_KEY_SERVICE_BLOCKED"
      assert reason =~ "blocked"
    end

    test "surfaces the HTTP status and message for other non-200 responses" do
      mock(fn _env ->
        %Tesla.Env{
          status: 500,
          body: %{"error" => %{"message" => "internal error"}}
        }
      end)

      assert {:error, reason} = Translate.parse("api_key", "Hello World", @languages)
      assert reason =~ "500"
      assert reason =~ "internal error"
    end

    test "does not leak the API key when the transport call itself fails" do
      mock(fn _env -> {:error, :timeout} end)

      assert {:error, reason} = Translate.parse("super-secret-api-key", "Hello World", @languages)
      refute reason =~ "super-secret-api-key"
    end

    test "does not crash when Google sends a malformed (non-list) details field" do
      mock(fn _env ->
        %Tesla.Env{
          status: 400,
          body: %{
            "error" => %{
              "message" => "Bad request",
              "details" => nil
            }
          }
        }
      end)

      assert {:error, reason} = Translate.parse("api_key", "Hello World", @languages)
      assert reason =~ "400"
      assert reason =~ "Bad request"
    end
  end
end
