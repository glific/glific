defmodule Glific.Templates.BlocksTest do
  use ExUnit.Case, async: true

  alias Glific.Flows.MessageVarParser
  alias Glific.Templates.Blocks

  @image_panel_envelope %{
    "type" => "blocks",
    "version" => 1,
    "component" => "glific/image-panel",
    "props" => %{
      "id" => "course",
      "body" => %{"kind" => "text", "value" => "Pick a course"},
      "options" => %{
        "kind" => "list",
        "value" => [
          %{
            "id" => "c1",
            "image" => %{"kind" => "image", "value" => "https://example.com/english.png"},
            "label" => %{"kind" => "text", "value" => "Spoken English"}
          },
          %{
            "id" => "c2",
            "image" => %{"kind" => "image", "value" => "https://example.com/digital.png"},
            "label" => %{"kind" => "text", "value" => "Digital skills"}
          }
        ]
      }
    }
  }

  @carousel_envelope %{
    "type" => "blocks",
    "version" => 1,
    "component" => "glific/carousel",
    "props" => %{
      "id" => "product",
      "cards" => %{
        "kind" => "list",
        "value" => [
          %{
            "id" => "p1",
            "image" => %{"kind" => "image", "value" => "https://example.com/a.png"},
            "image_alt" => %{"kind" => "alt", "value" => "Students at desks"},
            "title" => %{"kind" => "text", "value" => "Course A"}
          }
        ]
      }
    }
  }

  @form_envelope %{
    "type" => "blocks",
    "version" => 1,
    "component" => "glific/form",
    "props" => %{
      "fields" => %{
        "kind" => "list",
        "value" => [
          %{"id" => "name", "label" => %{"kind" => "text", "value" => "Your name"}}
        ]
      }
    }
  }

  @org_envelope %{
    "type" => "blocks",
    "version" => 1,
    "component" => "tap/course-picker",
    "props" => %{"anything" => "goes"}
  }

  # `validate_response/2` and `auto_summary/3` are called with `outbound.interactive_content`,
  # which is always the *unwrapped* form (contract §2) — messages persist the wire shape, not
  # the typed one. These mirror the typed fixtures above, unwrapped.
  @image_panel_unwrapped Blocks.unwrap(@image_panel_envelope)
  @carousel_unwrapped Blocks.unwrap(@carousel_envelope)
  @form_unwrapped Blocks.unwrap(@form_envelope)
  @org_unwrapped Blocks.unwrap(@org_envelope)

  describe "validate_payload/1 — generic envelope checks" do
    test "accepts a well-formed glific/image-panel payload" do
      assert :ok == Blocks.validate_payload(@image_panel_envelope)
    end

    test "accepts a well-formed org-namespace payload without inspecting props" do
      assert :ok == Blocks.validate_payload(@org_envelope)
    end

    test "rejects a payload with the wrong 'type'" do
      payload = Map.put(@org_envelope, "type", "custom_ui")
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "type"
    end

    test "rejects a payload with a string 'version'" do
      payload = Map.put(@org_envelope, "version", "1")
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "version"
    end

    test "rejects a component that does not match the namespaced format" do
      payload = Map.put(@org_envelope, "component", "Not Valid!")
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "component"
    end

    test "rejects a component using an underscore instead of a hyphen" do
      payload = Map.put(@org_envelope, "component", "tap/course_picker")
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "component"
    end

    test "rejects an unpublished glific/* component name" do
      payload = Map.put(@image_panel_envelope, "component", "glific/does-not-exist")
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "not a published"
    end

    test "rejects a payload exceeding the outbound size cap" do
      huge_options =
        Enum.map(1..10, fn i ->
          %{
            "id" => "c#{i}",
            "image" => %{"kind" => "image", "value" => "https://example.com/#{i}.png"},
            "label" => %{"kind" => "text", "value" => String.duplicate("x", 10_000)}
          }
        end)

      payload = put_in(@image_panel_envelope, ["props", "options", "value"], huge_options)
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "exceeds"
    end

    test "rejects a payload exceeding the max JSON depth" do
      deeply_nested =
        Enum.reduce(1..12, "leaf", fn _i, acc -> %{"nested" => acc} end)

      payload = Map.put(@org_envelope, "props", %{"deep" => deeply_nested})
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "depth"
    end

    test "rejects a non-map payload" do
      assert {:error, _reason} = Blocks.validate_payload("not a map")
    end
  end

  describe "validate_payload/1 — typed nodes (§2.1)" do
    test "rejects an unknown 'kind'" do
      payload = put_in(@org_envelope, ["props", "anything"], %{"kind" => "weird", "value" => "x"})
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "kind"
    end

    test "rejects a typed node with an extra key" do
      payload =
        put_in(@org_envelope, ["props", "anything"], %{
          "kind" => "text",
          "value" => "x",
          "extra" => "nope"
        })

      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "unknown key"
    end

    test "rejects a 'text' node whose value is not a string" do
      payload = put_in(@org_envelope, ["props", "anything"], %{"kind" => "text", "value" => 1})
      assert {:error, _reason} = Blocks.validate_payload(payload)
    end

    test "rejects an 'image' node whose value is not an absolute http(s) URL" do
      payload =
        put_in(@org_envelope, ["props", "anything"], %{"kind" => "image", "value" => "not-a-url"})

      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "http(s)"
    end

    test "accepts translate: false on a text node" do
      payload =
        put_in(@org_envelope, ["props", "anything"], %{
          "kind" => "text",
          "value" => "Brand Name",
          "translate" => false
        })

      assert :ok == Blocks.validate_payload(payload)
    end

    test "accepts number and boolean typed nodes" do
      payload =
        @org_envelope
        |> put_in(["props", "count"], %{"kind" => "number", "value" => 5})
        |> put_in(["props", "flag"], %{"kind" => "boolean", "value" => true})

      assert :ok == Blocks.validate_payload(payload)
    end

    test "accepts an 'alt' node" do
      payload =
        put_in(@org_envelope, ["props", "caption"], %{"kind" => "alt", "value" => "A cat"})

      assert :ok == Blocks.validate_payload(payload)
    end

    test "rejects an 'alt' node whose value is not a string" do
      payload = put_in(@org_envelope, ["props", "caption"], %{"kind" => "alt", "value" => 1})
      assert {:error, _reason} = Blocks.validate_payload(payload)
    end
  end

  # §2.1 calls a map with extra keys "a plain value", while §7 requires typed nodes to have
  # none of them. The resolution: the validator rejects anything carrying `kind` that is not a
  # fully valid node, so a typo can never be saved and later ship to the widget as a raw,
  # unrenderable object. The walker (see the `unwrap/1` describe block below) stays permissive
  # instead — it just recurses into a near-miss as a plain map — because rejecting malformed
  # payloads is validate_payload/1's job at save time, not unwrap/1's at send time.
  describe "validate_payload/1 — near-miss typed nodes are a validation error (§2.1/§7)" do
    test "rejects a node with a misspelled 'value' key ('val' instead)" do
      payload = put_in(@org_envelope, ["props", "anything"], %{"kind" => "text", "val" => "x"})
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "unknown key"
    end

    test "rejects a node with 'kind' but no 'value' at all" do
      payload = put_in(@org_envelope, ["props", "anything"], %{"kind" => "text"})
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "value"
    end

    test "rejects a node with an unrecognized 'kind'" do
      payload =
        put_in(@org_envelope, ["props", "anything"], %{"kind" => "richtext", "value" => "x"})

      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "kind"
    end
  end

  describe "validate_payload/1 — reserved ids (§5.1)" do
    test "rejects props.id equal to a reserved key" do
      payload = put_in(@carousel_envelope, ["props", "id"], "input")
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "reserved"
    end

    test "rejects a card id equal to a reserved key" do
      payload =
        put_in(@carousel_envelope, ["props", "cards", "value", Access.at(0), "id"], "value")

      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "reserved"
    end
  end

  describe "validate_payload/1 — glific/image-panel props" do
    test "rejects fewer than 1 option" do
      payload = put_in(@image_panel_envelope, ["props", "options", "value"], [])
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "between 1 and 10"
    end

    test "rejects more than 10 options" do
      options =
        Enum.map(1..11, fn i ->
          %{
            "id" => "c#{i}",
            "image" => %{"kind" => "image", "value" => "https://x/#{i}.png"},
            "label" => %{"kind" => "text", "value" => "L#{i}"}
          }
        end)

      payload = put_in(@image_panel_envelope, ["props", "options", "value"], options)
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "between 1 and 10"
    end

    test "rejects duplicate option ids" do
      options = [
        %{
          "id" => "c1",
          "image" => %{"kind" => "image", "value" => "https://x/1.png"},
          "label" => %{"kind" => "text", "value" => "A"}
        },
        %{
          "id" => "c1",
          "image" => %{"kind" => "image", "value" => "https://x/2.png"},
          "label" => %{"kind" => "text", "value" => "B"}
        }
      ]

      payload = put_in(@image_panel_envelope, ["props", "options", "value"], options)
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "unique"
    end

    test "rejects an unknown props key" do
      payload = put_in(@image_panel_envelope, ["props", "unexpected"], "value")
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "unknown key"
    end

    test "rejects an option missing the required 'image' key" do
      options = [%{"id" => "c1", "label" => %{"kind" => "text", "value" => "Spoken English"}}]
      payload = put_in(@image_panel_envelope, ["props", "options", "value"], options)
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "missing required key"
    end

    test "rejects an option with an unknown key" do
      options = [
        %{
          "id" => "c1",
          "image" => %{"kind" => "image", "value" => "https://x/1.png"},
          "label" => %{"kind" => "text", "value" => "A"},
          "unexpected" => "nope"
        }
      ]

      payload = put_in(@image_panel_envelope, ["props", "options", "value"], options)
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "unknown key"
    end

    test "rejects an option whose 'image' node is typed 'text' instead of 'image'" do
      options = [
        %{
          "id" => "c1",
          "image" => %{"kind" => "text", "value" => "https://x/1.png"},
          "label" => %{"kind" => "text", "value" => "A"}
        }
      ]

      payload = put_in(@image_panel_envelope, ["props", "options", "value"], options)
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "image"
    end
  end

  describe "validate_payload/1 — glific/carousel props" do
    test "rejects a card missing the required 'image' key" do
      cards = [%{"id" => "p1", "title" => %{"kind" => "text", "value" => "Course A"}}]
      payload = put_in(@carousel_envelope, ["props", "cards", "value"], cards)
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "missing required key"
    end

    test "rejects a card with an unknown key" do
      cards = [
        %{
          "id" => "p1",
          "image" => %{"kind" => "image", "value" => "https://x/1.png"},
          "title" => %{"kind" => "text", "value" => "Course A"},
          "unexpected" => "nope"
        }
      ]

      payload = put_in(@carousel_envelope, ["props", "cards", "value"], cards)
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "unknown key"
    end
  end

  describe "validate_payload/1 — glific/form props" do
    test "accepts a well-formed form payload" do
      assert :ok == Blocks.validate_payload(@form_envelope)
    end

    test "rejects more than 10 fields" do
      fields =
        Enum.map(1..11, fn i ->
          %{"id" => "f#{i}", "label" => %{"kind" => "text", "value" => "Field #{i}"}}
        end)

      payload = put_in(@form_envelope, ["props", "fields", "value"], fields)
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "between 1 and 10"
    end

    test "accepts a field with the optional 'placeholder' and 'required' keys" do
      fields = [
        %{
          "id" => "name",
          "label" => %{"kind" => "text", "value" => "Your name"},
          "placeholder" => %{"kind" => "text", "value" => "Asha"},
          "required" => %{"kind" => "boolean", "value" => true}
        }
      ]

      payload = put_in(@form_envelope, ["props", "fields", "value"], fields)
      assert :ok == Blocks.validate_payload(payload)
    end

    test "rejects a field with an unknown key" do
      fields = [
        %{
          "id" => "name",
          "label" => %{"kind" => "text", "value" => "Your name"},
          "unexpected" => "nope"
        }
      ]

      payload = put_in(@form_envelope, ["props", "fields", "value"], fields)
      assert {:error, reason} = Blocks.validate_payload(payload)
      assert reason =~ "unknown key"
    end
  end

  describe "validate_payload/1 — envelope survives Flows.MessageVarParser.parse_map/2" do
    # `contact_action.ex` runs a flow's outbound `interactive_content` through
    # `MessageVarParser.parse_map/2` before `unwrap/1` and
    # `Messages.check_for_hsm_message/2`'s validation guard. `parse_map/2` recurses over the
    # map/list, running `parse/2` on every string leaf (and key) — these tests pin that a
    # flow-parsed typed envelope still validates: keys are untouched, non-string leaves
    # (`required: true`) pass through unchanged, and a `@contact...` reference inside a text
    # node's `value` resolves without breaking the surrounding structure.
    test "a flow-parsed glific/image-panel envelope with a body variable still validates" do
      envelope =
        put_in(
          @image_panel_envelope,
          ["props", "body", "value"],
          "Hi @contact.fields.name, pick a course"
        )

      parsed =
        MessageVarParser.parse_map(envelope, %{"contact" => %{"fields" => %{"name" => "Asha"}}})

      assert parsed["props"]["body"]["value"] == "Hi Asha, pick a course"
      assert :ok == Blocks.validate_payload(parsed)
    end

    test "a flow-parsed glific/carousel envelope still validates" do
      parsed = MessageVarParser.parse_map(@carousel_envelope, %{})
      assert :ok == Blocks.validate_payload(parsed)
    end

    test "a flow-parsed glific/form envelope with placeholder/required fields still validates" do
      envelope =
        put_in(@form_envelope, ["props", "fields", "value"], [
          %{
            "id" => "name",
            "label" => %{"kind" => "text", "value" => "Your name"},
            "placeholder" => %{"kind" => "text", "value" => "e.g. Asha"},
            "required" => %{"kind" => "boolean", "value" => true}
          }
        ])

      parsed = MessageVarParser.parse_map(envelope, %{})
      assert :ok == Blocks.validate_payload(parsed)
    end
  end

  describe "validate_response/2 — generic envelope checks" do
    test "accepts a valid glific/image-panel response" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/image-panel",
        "values" => %{"course" => "c2"},
        "summary" => "Picked Digital skills"
      }

      assert :ok == Blocks.validate_response(response, @image_panel_unwrapped)
    end

    test "accepts a valid org-namespace response without inspecting values" do
      response = %{
        "message_id" => 4211,
        "component" => "tap/course-picker",
        "values" => %{"anything" => "goes here"},
        "summary" => "Picked something"
      }

      assert :ok == Blocks.validate_response(response, @org_unwrapped)
    end

    test "rejects a response missing summary" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/image-panel",
        "values" => %{"course" => "c2"}
      }

      assert {:error, _reason} = Blocks.validate_response(response, @image_panel_unwrapped)
    end

    test "rejects a summary exceeding 500 characters" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/image-panel",
        "values" => %{"course" => "c2"},
        "summary" => String.duplicate("x", 501)
      }

      assert {:error, reason} = Blocks.validate_response(response, @image_panel_unwrapped)
      assert reason =~ "exceeds"
    end

    test "rejects a component echo that does not match the outbound envelope" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/carousel",
        "values" => %{"course" => "c2"},
        "summary" => "Picked Digital skills"
      }

      assert {:error, reason} = Blocks.validate_response(response, @image_panel_unwrapped)
      assert reason =~ "does not match"
    end

    test "rejects a response exceeding the inbound size cap" do
      response = %{
        "message_id" => 4211,
        "component" => "tap/course-picker",
        "values" => %{"blob" => String.duplicate("x", 20_000)},
        "summary" => "Picked something"
      }

      assert {:error, reason} = Blocks.validate_response(response, @org_unwrapped)
      assert reason =~ "exceeds"
    end

    test "rejects a response exceeding the max JSON depth" do
      deeply_nested =
        Enum.reduce(1..12, "leaf", fn _i, acc -> %{"nested" => acc} end)

      response = %{
        "message_id" => 4211,
        "component" => "tap/course-picker",
        "values" => %{"deep" => deeply_nested},
        "summary" => "Picked something"
      }

      assert {:error, reason} = Blocks.validate_response(response, @org_unwrapped)
      assert reason =~ "depth"
    end
  end

  describe "validate_response/2 — glific/image-panel and glific/carousel values" do
    test "rejects a selected id that is not one of the offered options" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/image-panel",
        "values" => %{"course" => "not-an-option"},
        "summary" => "Picked something"
      }

      assert {:error, reason} = Blocks.validate_response(response, @image_panel_unwrapped)
      assert reason =~ "not one of the offered"
    end

    test "rejects a values map with extra keys" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/image-panel",
        "values" => %{"course" => "c2", "extra" => "nope"},
        "summary" => "Picked Digital skills"
      }

      assert {:error, _reason} = Blocks.validate_response(response, @image_panel_unwrapped)
    end

    test "accepts a valid carousel selection" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/carousel",
        "values" => %{"product" => "p1"},
        "summary" => "Picked Course A"
      }

      assert :ok == Blocks.validate_response(response, @carousel_unwrapped)
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

      assert :ok == Blocks.validate_response(response, @form_unwrapped)
    end

    test "rejects a values map missing a field id" do
      response = %{
        "message_id" => 4211,
        "component" => "glific/form",
        "values" => %{},
        "summary" => "Your name: "
      }

      assert {:error, _reason} = Blocks.validate_response(response, @form_unwrapped)
    end
  end

  describe "catalog/0" do
    test "publishes exactly the v1 built-in blocks" do
      assert Map.keys(Blocks.catalog()) |> Enum.sort() ==
               ["glific/carousel", "glific/form", "glific/image-panel"]
    end
  end

  describe "unwrap/1" do
    test "collapses a typed node found inside props to its value" do
      envelope =
        put_in(@org_envelope, ["props", "greeting"], %{"kind" => "text", "value" => "hello"})

      assert Blocks.unwrap(envelope)["props"]["greeting"] == "hello"
    end

    test "collapses a typed list node inside props recursively" do
      envelope =
        put_in(@org_envelope, ["props", "items"], %{
          "kind" => "list",
          "value" => [%{"id" => "c1", "label" => %{"kind" => "text", "value" => "A"}}]
        })

      assert Blocks.unwrap(envelope)["props"]["items"] == [%{"id" => "c1", "label" => "A"}]
    end

    test "unwraps a full envelope's props uniformly" do
      assert Blocks.unwrap(@image_panel_envelope)["props"] == %{
               "id" => "course",
               "body" => "Pick a course",
               "options" => [
                 %{
                   "id" => "c1",
                   "image" => "https://example.com/english.png",
                   "label" => "Spoken English"
                 },
                 %{
                   "id" => "c2",
                   "image" => "https://example.com/digital.png",
                   "label" => "Digital skills"
                 }
               ]
             }
    end

    test "leaves type/version/component untouched" do
      unwrapped = Blocks.unwrap(@image_panel_envelope)
      assert unwrapped["type"] == "blocks"
      assert unwrapped["version"] == 1
      assert unwrapped["component"] == "glific/image-panel"
    end

    # contract §2 promises context is echoed back verbatim; the walker is shape-based, not
    # key-based, so scoping unwrap to props (rather than walking the whole envelope) is what
    # keeps a {kind, value}-shaped map an org happens to put in context from being silently
    # collapsed into something different from what it sent.
    test "leaves a {kind, value}-shaped map inside context untouched" do
      envelope =
        Map.put(@org_envelope, "context", %{
          "kind" => "text",
          "value" => "not a typed node here"
        })

      assert Blocks.unwrap(envelope)["context"] == %{
               "kind" => "text",
               "value" => "not a typed node here"
             }
    end

    test "passes through an envelope with no 'props' key" do
      assert Blocks.unwrap(%{"a" => 1, "b" => "c"}) == %{"a" => 1, "b" => "c"}
    end

    # The walker stays permissive on a near-miss typed node (unlike the strict validator, see
    # the "near-miss typed nodes" describe block above) — it recurses into it as a plain map
    # rather than collapsing or raising, so unwrapping is always total.
    test "recurses into a near-miss typed node inside props instead of collapsing or raising" do
      envelope = put_in(@org_envelope, ["props", "broken"], %{"kind" => "text", "val" => "x"})
      assert Blocks.unwrap(envelope)["props"]["broken"] == %{"kind" => "text", "val" => "x"}
    end
  end

  describe "derive_body/1" do
    test "joins every 'text' node's value with an em dash, walking into typed lists" do
      assert Blocks.derive_body(@carousel_envelope) == "Course A"
    end

    test "skips 'alt' nodes entirely — alt text never leaks into the derived body" do
      refute Blocks.derive_body(@carousel_envelope) =~ "Students at desks"
    end

    test "collects nested text nodes from image-panel props and body" do
      body = Blocks.derive_body(@image_panel_envelope)
      assert body =~ "Pick a course"
      assert body =~ "Spoken English"
      assert body =~ "Digital skills"
    end

    test "returns an empty string for a Custom Block with no text nodes" do
      envelope =
        put_in(@org_envelope, ["props"], %{"count" => %{"kind" => "number", "value" => 5}})

      assert Blocks.derive_body(envelope) == ""
    end

    test "returns an empty string for a block whose only text-like node is 'alt'" do
      envelope =
        put_in(@org_envelope, ["props", "caption"], %{"kind" => "alt", "value" => "A cat"})

      assert Blocks.derive_body(envelope) == ""
    end

    test "drops empty/whitespace-only text nodes rather than emitting a blank em dash" do
      envelope =
        put_in(@carousel_envelope, ["props", "body"], %{"kind" => "text", "value" => "   "})

      assert Blocks.derive_body(envelope) == "Course A"
    end

    test "clamps to 500 characters" do
      envelope =
        put_in(@org_envelope, ["props", "text"], %{
          "kind" => "text",
          "value" => String.duplicate("x", 600)
        })

      assert String.length(Blocks.derive_body(envelope)) == 500
    end
  end

  describe "collect_translatable_nodes/1 and put_translated_nodes/2" do
    test "collects both 'text' and 'alt' node values, paired with their paths" do
      nodes = Blocks.collect_translatable_nodes(@carousel_envelope)
      values = Enum.map(nodes, fn {_path, value} -> value end)

      assert "Course A" in values
      assert "Students at desks" in values
    end

    test "reinserts translated text at the exact same paths, not positionally" do
      nodes = Blocks.collect_translatable_nodes(@carousel_envelope)
      translated = Enum.map(nodes, fn {path, _value} -> {path, "TRANSLATED"} end)

      updated = Blocks.put_translated_nodes(@carousel_envelope, translated)

      assert get_in(updated, ["props", "cards", "value", Access.at(0), "title", "value"]) ==
               "TRANSLATED"

      assert get_in(updated, ["props", "cards", "value", Access.at(0), "image_alt", "value"]) ==
               "TRANSLATED"

      # the image node (untranslatable) is left untouched
      assert get_in(updated, ["props", "cards", "value", Access.at(0), "image", "value"]) ==
               "https://example.com/a.png"
    end
  end

  describe "auto_summary/3" do
    test "returns the selected option's label for glific/image-panel" do
      assert Blocks.auto_summary("glific/image-panel", @image_panel_unwrapped["props"], %{
               "course" => "c2"
             }) == "Digital skills"
    end

    test "returns the selected card's title for glific/carousel" do
      assert Blocks.auto_summary("glific/carousel", @carousel_unwrapped["props"], %{
               "product" => "p1"
             }) == "Course A"
    end

    test "returns joined label:value pairs for glific/form" do
      assert Blocks.auto_summary("glific/form", @form_unwrapped["props"], %{"name" => "Asha"}) ==
               "Your name: Asha"
    end

    test "returns nil for an org namespace" do
      assert Blocks.auto_summary("tap/course-picker", %{}, %{}) == nil
    end

    test "skips fields the contact left empty" do
      props = %{
        "fields" => [
          %{"id" => "name", "label" => "Your name"},
          %{"id" => "email", "label" => "Your email"}
        ]
      }

      assert Blocks.auto_summary("glific/form", props, %{"name" => "Asha", "email" => ""}) ==
               "Your name: Asha"
    end

    test "never returns a blank summary when every field was left empty" do
      props = %{
        "fields" => [
          %{"id" => "name", "label" => "Your name"},
          %{"id" => "email", "label" => "Your email"}
        ]
      }

      summary = Blocks.auto_summary("glific/form", props, %{"name" => "", "email" => ""})
      assert summary != ""
      assert is_binary(summary)
    end
  end
end
