defmodule Glific.Templates.CustomUiTest do
  use ExUnit.Case, async: true

  alias Glific.Templates.CustomUi

  @image_panel_envelope %{
    "type" => "custom_ui",
    "version" => "1",
    "component" => "glific/image_panel",
    "props" => %{
      "id" => "course",
      "body" => "Pick a course",
      "options" => [
        %{
          "id" => "c1",
          "image" => "https://example.com/english.png",
          "label" => "Spoken English"
        },
        %{"id" => "c2", "image" => "https://example.com/digital.png", "label" => "Digital skills"}
      ]
    },
    "fallback" => "Reply with a course: Spoken English or Digital skills"
  }

  @carousel_envelope %{
    "type" => "custom_ui",
    "version" => "1",
    "component" => "glific/carousel",
    "props" => %{
      "id" => "product",
      "cards" => [
        %{"id" => "p1", "image" => "https://example.com/a.png", "title" => "Course A"}
      ]
    },
    "fallback" => "Browse our courses"
  }

  @form_envelope %{
    "type" => "custom_ui",
    "version" => "1",
    "component" => "glific/form",
    "props" => %{
      "fields" => [%{"id" => "name", "label" => "Your name"}]
    },
    "fallback" => "Tell us about yourself"
  }

  @org_envelope %{
    "type" => "custom_ui",
    "version" => "1",
    "component" => "tap/course_picker",
    "props" => %{"anything" => "goes"},
    "fallback" => "Pick a course: reply with its name"
  }

  describe "validate_payload/1 — generic envelope checks" do
    test "accepts a well-formed glific/image_panel payload" do
      assert :ok == CustomUi.validate_payload(@image_panel_envelope)
    end

    test "accepts a well-formed org-namespace payload without inspecting props" do
      assert :ok == CustomUi.validate_payload(@org_envelope)
    end

    test "rejects a payload missing fallback" do
      payload = Map.delete(@image_panel_envelope, "fallback")
      assert {:error, _reason} = CustomUi.validate_payload(payload)
    end

    test "rejects a payload with a blank fallback" do
      payload = Map.put(@image_panel_envelope, "fallback", "")
      assert {:error, _reason} = CustomUi.validate_payload(payload)
    end

    test "rejects a component that does not match the namespaced format" do
      payload = Map.put(@org_envelope, "component", "Not Valid!")
      assert {:error, reason} = CustomUi.validate_payload(payload)
      assert reason =~ "component"
    end

    test "rejects an unpublished glific/* component name" do
      payload = Map.put(@image_panel_envelope, "component", "glific/does_not_exist")
      assert {:error, reason} = CustomUi.validate_payload(payload)
      assert reason =~ "not a published"
    end

    test "rejects a payload exceeding the outbound size cap" do
      huge_options =
        Enum.map(1..10, fn i ->
          %{
            "id" => "c#{i}",
            "image" => "https://example.com/#{i}.png",
            "label" => String.duplicate("x", 10_000)
          }
        end)

      payload = put_in(@image_panel_envelope, ["props", "options"], huge_options)
      assert {:error, reason} = CustomUi.validate_payload(payload)
      assert reason =~ "exceeds"
    end

    test "rejects a payload exceeding the max JSON depth" do
      deeply_nested =
        Enum.reduce(1..12, "leaf", fn _i, acc -> %{"nested" => acc} end)

      payload = Map.put(@org_envelope, "props", %{"deep" => deeply_nested})
      assert {:error, reason} = CustomUi.validate_payload(payload)
      assert reason =~ "depth"
    end

    test "rejects a non-map payload" do
      assert {:error, _reason} = CustomUi.validate_payload("not a map")
    end
  end

  describe "validate_payload/1 — glific/image_panel props" do
    test "rejects fewer than 1 option" do
      payload = put_in(@image_panel_envelope, ["props", "options"], [])
      assert {:error, reason} = CustomUi.validate_payload(payload)
      assert reason =~ "between 1 and 10"
    end

    test "rejects more than 10 options" do
      options =
        Enum.map(1..11, fn i ->
          %{"id" => "c#{i}", "image" => "https://x/#{i}.png", "label" => "L#{i}"}
        end)

      payload = put_in(@image_panel_envelope, ["props", "options"], options)
      assert {:error, reason} = CustomUi.validate_payload(payload)
      assert reason =~ "between 1 and 10"
    end

    test "rejects duplicate option ids" do
      options = [
        %{"id" => "c1", "image" => "https://x/1.png", "label" => "A"},
        %{"id" => "c1", "image" => "https://x/2.png", "label" => "B"}
      ]

      payload = put_in(@image_panel_envelope, ["props", "options"], options)
      assert {:error, reason} = CustomUi.validate_payload(payload)
      assert reason =~ "unique"
    end

    test "rejects an unknown props key" do
      payload = put_in(@image_panel_envelope, ["props", "unexpected"], "value")
      assert {:error, reason} = CustomUi.validate_payload(payload)
      assert reason =~ "unknown key"
    end
  end

  describe "validate_payload/1 — glific/form props" do
    test "accepts a well-formed form payload" do
      assert :ok == CustomUi.validate_payload(@form_envelope)
    end

    test "rejects more than 10 fields" do
      fields = Enum.map(1..11, fn i -> %{"id" => "f#{i}", "label" => "Field #{i}"} end)
      payload = put_in(@form_envelope, ["props", "fields"], fields)
      assert {:error, reason} = CustomUi.validate_payload(payload)
      assert reason =~ "between 1 and 10"
    end
  end

  describe "validate_response/2 — generic envelope checks" do
    test "accepts a valid glific/image_panel response" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/image_panel",
        "values" => %{"course" => "c2"},
        "summary" => "Picked Digital skills"
      }

      assert :ok == CustomUi.validate_response(response, @image_panel_envelope)
    end

    test "accepts a valid org-namespace response without inspecting values" do
      response = %{
        "message_id" => 4211,
        "component" => "tap/course_picker",
        "values" => %{"anything" => "goes here"},
        "summary" => "Picked something"
      }

      assert :ok == CustomUi.validate_response(response, @org_envelope)
    end

    test "rejects a response missing summary" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/image_panel",
        "values" => %{"course" => "c2"}
      }

      assert {:error, _reason} = CustomUi.validate_response(response, @image_panel_envelope)
    end

    test "rejects a summary exceeding 500 characters" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/image_panel",
        "values" => %{"course" => "c2"},
        "summary" => String.duplicate("x", 501)
      }

      assert {:error, reason} = CustomUi.validate_response(response, @image_panel_envelope)
      assert reason =~ "exceeds"
    end

    test "rejects a component echo that does not match the outbound envelope" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/carousel",
        "values" => %{"course" => "c2"},
        "summary" => "Picked Digital skills"
      }

      assert {:error, reason} = CustomUi.validate_response(response, @image_panel_envelope)
      assert reason =~ "does not match"
    end

    test "rejects a response exceeding the inbound size cap" do
      response = %{
        "message_id" => 4211,
        "component" => "tap/course_picker",
        "values" => %{"blob" => String.duplicate("x", 20_000)},
        "summary" => "Picked something"
      }

      assert {:error, reason} = CustomUi.validate_response(response, @org_envelope)
      assert reason =~ "exceeds"
    end

    test "rejects a response exceeding the max JSON depth" do
      deeply_nested =
        Enum.reduce(1..12, "leaf", fn _i, acc -> %{"nested" => acc} end)

      response = %{
        "message_id" => 4211,
        "component" => "tap/course_picker",
        "values" => %{"deep" => deeply_nested},
        "summary" => "Picked something"
      }

      assert {:error, reason} = CustomUi.validate_response(response, @org_envelope)
      assert reason =~ "depth"
    end
  end

  describe "validate_response/2 — glific/image_panel and glific/carousel values" do
    test "rejects a selected id that is not one of the offered options" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/image_panel",
        "values" => %{"course" => "not-an-option"},
        "summary" => "Picked something"
      }

      assert {:error, reason} = CustomUi.validate_response(response, @image_panel_envelope)
      assert reason =~ "not one of the offered"
    end

    test "rejects a values map with extra keys" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/image_panel",
        "values" => %{"course" => "c2", "extra" => "nope"},
        "summary" => "Picked Digital skills"
      }

      assert {:error, _reason} = CustomUi.validate_response(response, @image_panel_envelope)
    end

    test "accepts a valid carousel selection" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/carousel",
        "values" => %{"product" => "p1"},
        "summary" => "Picked Course A"
      }

      assert :ok == CustomUi.validate_response(response, @carousel_envelope)
    end
  end

  describe "validate_response/2 — glific/form values" do
    test "accepts a values map with one string per field id" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/form",
        "values" => %{"name" => "Asha"},
        "summary" => "Your name: Asha"
      }

      assert :ok == CustomUi.validate_response(response, @form_envelope)
    end

    test "rejects a values map missing a field id" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/form",
        "values" => %{},
        "summary" => "Your name: "
      }

      assert {:error, _reason} = CustomUi.validate_response(response, @form_envelope)
    end
  end

  describe "catalog/0" do
    test "publishes exactly the v0 built-in blocks" do
      assert Map.keys(CustomUi.catalog()) |> Enum.sort() ==
               ["glific/carousel", "glific/form", "glific/image_panel"]
    end
  end

  describe "auto_summary/3" do
    test "returns the selected option's label for glific/image_panel" do
      assert CustomUi.auto_summary("glific/image_panel", @image_panel_envelope["props"], %{
               "course" => "c2"
             }) == "Digital skills"
    end

    test "returns the selected card's title for glific/carousel" do
      assert CustomUi.auto_summary("glific/carousel", @carousel_envelope["props"], %{
               "product" => "p1"
             }) == "Course A"
    end

    test "returns joined label:value pairs for glific/form" do
      assert CustomUi.auto_summary("glific/form", @form_envelope["props"], %{"name" => "Asha"}) ==
               "Your name: Asha"
    end

    test "returns nil for an org namespace" do
      assert CustomUi.auto_summary("tap/course_picker", %{}, %{}) == nil
    end
  end
end
