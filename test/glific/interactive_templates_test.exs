defmodule Glific.InteractiveTemplatesTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Fixtures,
    Templates.InteractiveTemplate,
    Templates.InteractiveTemplates
  }

  describe "interactive_templates" do
    @valid_attrs %{
      label: "Quick Reply Test Text",
      type: :quick_reply,
      interactive_content: %{
        "type" => "quick_reply",
        "content" => %{
          "type" => "text",
          "text" => "How excited are you for Glific?"
        },
        "options" => [
          %{
            "type" => "text",
            "title" => "Excited"
          },
          %{
            "type" => "text",
            "title" => "Very Excited"
          }
        ]
      }
    }

    @valid_more_attrs %{
      label: "Quick Reply Test Text 2",
      type: :quick_reply,
      interactive_content: %{
        "type" => "quick_reply",
        "content" => %{
          "type" => "text",
          "text" => "How was your experience with Glific?"
        },
        "options" => [
          %{
            "type" => "text",
            "title" => "Great"
          },
          %{
            "type" => "text",
            "title" => "Awesome"
          }
        ]
      }
    }

    @valid_url_attrs %{
      label: "Quick Reply Test Text 2",
      type: :quick_reply,
      interactive_content: %{
        "type" => "quick_reply",
        "content" => %{
          "type" => "image",
          "text" => "How was your experience with Glific?",
          "url" => "https://robohash.org/set_set2/bgset_bg1/mMs4U"
        },
        "options" => [
          %{
            "type" => "text",
            "title" => "Great"
          },
          %{
            "type" => "text",
            "title" => "Awesome"
          }
        ]
      },
      translations: %{
        "1" => %{
          "content" => %{
            "type" => "image",
            "text" => "How was your experience with Glific?",
            "url" => "https://robohash.org/set_set2/bgset_bg1/mMs4U"
          },
          "options" => [
            %{"title" => "Great", "type" => "text"},
            %{"title" => "Awesome", "type" => "text"}
          ],
          "type" => "quick_reply"
        },
        "2" => %{
          "content" => %{
            "text" => "ग्लिफ़िक त्वरित उत्तर का परीक्षण करें?",
            "type" => "image",
            "url" => "https://robohash.org/set_set2/bgset_bg1/mMs4U"
          },
          "options" => [
            %{"title" => "उत्कृष्ट", "type" => "text"},
            %{"title" => "शानदार", "type" => "text"}
          ],
          "type" => "quick_reply"
        }
      }
    }

    @valid_footer_attrs %{
      label: "Glific Features",
      type: :quick_reply,
      interactive_content: %{
        "type" => "quick_reply",
        "content" => %{
          "caption" => "caption is footer",
          "type" => "text",
          "text" => "How was your experience with Glific?"
        },
        "options" => [
          %{
            "type" => "text",
            "title" => "Great"
          },
          %{
            "type" => "text",
            "title" => "Awesome"
          }
        ]
      },
      translations: %{
        "1" => %{
          "content" => %{
            "caption" => "caption is footer",
            "header" => "Glific Features",
            "text" => "How was your experience with Glific?",
            "type" => "text"
          },
          "options" => [
            %{"title" => "Great", "type" => "text"},
            %{"title" => "Awesome", "type" => "text"}
          ],
          "type" => "quick_reply"
        }
      }
    }

    @expected_footer_attrs %{
      label: "Glific Features",
      type: :quick_reply,
      interactive_content: %{
        "type" => "quick_reply",
        "content" => %{
          "caption" => "caption is footer",
          "type" => "text",
          "text" => "How was your experience with Glific?"
        },
        "options" => [
          %{
            "type" => "text",
            "title" => "Great"
          },
          %{
            "type" => "text",
            "title" => "Awesome"
          }
        ]
      },
      translations: %{
        "1" => %{
          "content" => %{
            "caption" => "caption is footer",
            "header" => "Glific Features",
            "text" => "How was your experience with Glific?",
            "type" => "text"
          },
          "options" => [
            %{"title" => "Great", "type" => "text"},
            %{"title" => "Awesome", "type" => "text"}
          ],
          "type" => "quick_reply"
        },
        "2" => %{
          "content" => %{
            "caption" => "कैप्शन पाद लेख है",
            "header" => "शानदार विशेषताएं",
            "text" => "ग्लिफ़िक त्वरित उत्तर का परीक्षण करें?",
            "type" => "text"
          },
          "options" => [
            %{"title" => "उत्कृष्ट", "type" => "text"},
            %{"title" => "शानदार", "type" => "text"}
          ],
          "type" => "quick_reply"
        }
      }
    }

    @valid_location_attrs %{
      label: "Send Location",
      type: :location_request_message,
      interactive_content: %{
        "action" => %{"name" => "send_location"},
        "body" => %{"text" => "please share your location", "type" => "text"},
        "type" => "location_request_message"
      },
      translations: %{
        "1" => %{
          "action" => %{"name" => "send_location"},
          "body" => %{"text" => "please share your location", "type" => "text"},
          "type" => "location_request_message"
        }
      }
    }

    @expected_location_attrs %{
      label: "Send Location",
      type: :location_request_message,
      interactive_content: %{
        "action" => %{"name" => "send_location"},
        "body" => %{"text" => "please share your location", "type" => "text"},
        "type" => "location_request_message"
      },
      translations: %{
        "1" => %{
          "action" => %{"name" => "send_location"},
          "body" => %{"text" => "please share your location", "type" => "text"},
          "type" => "location_request_message"
        },
        "2" => %{
          "action" => %{"name" => "send_location"},
          "body" => %{
            "text" => "कृपया अपना स्थान साझा करें",
            "type" => "text"
          },
          "type" => "location_request_message"
        }
      }
    }

    @valid_list_attrs %{
      label: "Interactive list",
      type: :list,
      interactive_content: %{
        "body" => "How was your experience with Glific?",
        "globalButtons" => [%{"title" => "Glific Features", "type" => "text"}],
        "items" => [
          %{
            "options" => [
              %{
                "description" => "Awesome",
                "title" => "Great",
                "type" => "text"
              }
            ],
            "subtitle" => "Excitement level",
            "title" => "Excitement level"
          }
        ],
        "title" => "glific",
        "type" => "list"
      },
      translations: %{
        "1" => %{
          "body" => "How was your experience with Glific?",
          "globalButtons" => [%{"title" => "Glific Features", "type" => "text"}],
          "items" => [
            %{
              "options" => [
                %{
                  "description" => "Awesome",
                  "title" => "Great",
                  "type" => "text"
                }
              ],
              "subtitle" => "Excitement level",
              "title" => "Excitement level"
            }
          ],
          "title" => "glific",
          "type" => "list"
        }
      }
    }

    @expected_list_attrs %{
      label: "Interactive list",
      type: :list,
      interactive_content: %{
        "body" => "How was your experience with Glific?",
        "globalButtons" => [%{"title" => "Glific Features", "type" => "text"}],
        "items" => [
          %{
            "options" => [
              %{
                "description" => "Awesome",
                "title" => "Great",
                "type" => "text"
              }
            ],
            "subtitle" => "Excitement level",
            "title" => "Excitement level"
          }
        ],
        "title" => "glific",
        "type" => "list"
      },
      translations: %{
        "1" => %{
          "body" => "How was your experience with Glific?",
          "globalButtons" => [%{"title" => "Glific Features", "type" => "text"}],
          "items" => [
            %{
              "options" => [
                %{
                  "description" => "Awesome",
                  "title" => "Great",
                  "type" => "text"
                }
              ],
              "subtitle" => "Excitement level",
              "title" => "Excitement level"
            }
          ],
          "title" => "glific",
          "type" => "list"
        },
        "2" => %{
          "body" => "ग्लिफ़िक त्वरित उत्तर का परीक्षण करें?",
          "globalButtons" => [
            %{"title" => "शानदार विशेषताएं", "type" => "text"}
          ],
          "items" => [
            %{
              "options" => [
                %{
                  "description" => "शानदार",
                  "title" => "उत्कृष्ट",
                  "type" => "text"
                }
              ],
              "subtitle" => "उत्साह का स्तर",
              "title" => "उत्साह का स्तर"
            }
          ],
          "title" => "ग्लिफ़िक",
          "type" => "list"
        }
      }
    }

    @update_attrs %{
      label: "Updated Quick Reply label"
    }

    @invalid_attrs %{
      label: nil,
      type: :quick_reply,
      interactive_content: nil
    }

    test "count_interactive_templates/1 returns count of all interactives",
         %{organization_id: _organization_id} = attrs do
      interactive_count = InteractiveTemplates.count_interactive_templates(%{filter: attrs})
      _ = Fixtures.interactive_fixture(attrs)

      assert InteractiveTemplates.count_interactive_templates(%{filter: attrs}) ==
               interactive_count + 1

      _ = Fixtures.interactive_fixture(Map.merge(attrs, @valid_more_attrs))

      assert InteractiveTemplates.count_interactive_templates(%{filter: attrs}) ==
               interactive_count + 2

      assert InteractiveTemplates.count_interactive_templates(%{
               filter: Map.merge(attrs, %{label: "Quick Reply Test Text 2"})
             }) == 1
    end

    test "get_interactive_template!/1 returns the interactive with given id", %{
      organization_id: organization_id
    } do
      interactive = Fixtures.interactive_fixture(%{organization_id: organization_id})
      assert InteractiveTemplates.get_interactive_template!(interactive.id) == interactive
    end

    test "fetch_interactive_template/1 returns the interactive_template with given id or returns {:ok, interactive_template} or {:error, any}",
         %{organization_id: organization_id} do
      interactive_template = Fixtures.interactive_fixture(%{organization_id: organization_id})

      {:ok, fetched_interactive_template} =
        InteractiveTemplates.fetch_interactive_template(interactive_template.id)

      assert fetched_interactive_template.label == interactive_template.label
      assert fetched_interactive_template.type == interactive_template.type

      assert fetched_interactive_template.interactive_content ==
               interactive_template.interactive_content
    end

    test "create_interactive_template/1 with valid data creates an interactive message", %{
      organization_id: organization_id
    } do
      interactive = Fixtures.interactive_fixture(%{organization_id: organization_id})

      attrs =
        Map.merge(@valid_attrs, %{
          organization_id: organization_id,
          language_id: interactive.language_id
        })

      assert {:ok, %InteractiveTemplate{} = interactive} =
               InteractiveTemplates.create_interactive_template(attrs)

      assert interactive.label == "Quick Reply Test Text"
      assert interactive.type == :quick_reply
      assert interactive.organization_id == organization_id
    end

    test "create_interactive_template/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               InteractiveTemplates.create_interactive_template(@invalid_attrs)
    end

    test "update_interactive_template/2 with valid data updates the interactive", %{
      organization_id: organization_id
    } do
      interactive = Fixtures.interactive_fixture(%{organization_id: organization_id})

      assert {:ok, %InteractiveTemplate{} = interactive, _message} =
               InteractiveTemplates.update_interactive_template(interactive, @update_attrs)

      assert interactive.label == "Updated Quick Reply label"
      assert interactive.type == :quick_reply
    end

    test "update_interactive_template/2 with invalid data returns error changeset", %{
      organization_id: organization_id
    } do
      interactive = Fixtures.interactive_fixture(%{organization_id: organization_id})

      assert {:error, %Ecto.Changeset{}} =
               InteractiveTemplates.update_interactive_template(interactive, @invalid_attrs)

      assert interactive == InteractiveTemplates.get_interactive_template!(interactive.id)
    end

    test "delete_interactive_template/1 deletes an interactive", %{
      organization_id: organization_id
    } do
      interactive = Fixtures.interactive_fixture(%{organization_id: organization_id})

      assert {:ok, %InteractiveTemplate{}} =
               InteractiveTemplates.delete_interactive_template(interactive)

      assert_raise Ecto.NoResultsError, fn ->
        InteractiveTemplates.get_interactive_template!(interactive.id)
      end
    end

    test "list_interactives/1 with multiple items",
         %{organization_id: _organization_id} = attrs do
      interactive_count = InteractiveTemplates.count_interactive_templates(%{filter: attrs})

      interactive1 = Fixtures.interactive_fixture(attrs)
      interactive2 = Fixtures.interactive_fixture(Map.merge(@valid_more_attrs, attrs))
      interactives = InteractiveTemplates.list_interactives(%{filter: attrs})

      assert length(interactives) == interactive_count + 2

      assert interactive1 in interactives
      assert interactive2 in interactives
    end

    test "list_interactives/1 with multiple items sorted",
         %{organization_id: _organization_id} = attrs do
      interactive_count = InteractiveTemplates.count_interactive_templates(%{filter: attrs})

      Fixtures.interactive_fixture(attrs)
      Fixtures.interactive_fixture(Map.merge(attrs, @valid_more_attrs))

      interactives =
        InteractiveTemplates.list_interactives(%{opts: %{order: :asc}, filter: attrs})

      assert length(interactives) == interactive_count + 2
    end

    test "list_interactives/1 with items filtered",
         %{organization_id: _organization_id} = attrs do
      _interactive1 = Fixtures.interactive_fixture(attrs)
      interactive2 = Fixtures.interactive_fixture(Map.merge(@valid_more_attrs, attrs))

      interactives =
        InteractiveTemplates.list_interactives(%{
          opts: %{order: :asc},
          filter: Map.merge(%{label: "Quick Reply Test"}, attrs)
        })

      assert length(interactives) == 1
      [h] = interactives
      assert h == interactive2
    end

    test "list_interactives/1 with tag_ids filter on interactive_templates", attrs do
      tag = Fixtures.tag_fixture(Map.merge(attrs, %{label: "test_tag"}))
      interactives = Fixtures.interactive_fixture(Map.merge(attrs, %{tag_id: tag.id}))

      interactive_list =
        InteractiveTemplates.list_interactives(%{filter: Map.merge(attrs, %{tag_ids: [tag.id]})})

      assert interactive_list == [interactives]

      interactive_list = InteractiveTemplates.list_interactives(%{filter: %{term: tag.label}})

      assert interactive_list == [interactives]
    end

    test "list_interactives/1 with interactive type",
         %{organization_id: _organization_id} = attrs do
      interactive1 = Fixtures.interactive_fixture(attrs)
      interactive2 = Fixtures.interactive_fixture(Map.merge(@valid_more_attrs, attrs))

      interactives =
        InteractiveTemplates.list_interactives(%{
          opts: %{order: :asc},
          filter: Map.merge(%{type: :quick_reply}, attrs)
        })

      assert length(interactives) == 8
      assert interactive1 in interactives
      assert interactive2 in interactives
    end
  end

  setup_all do
    Tesla.Mock.mock_global(fn env ->
      cond do
        String.contains?(env.body, "Test glific quick reply?") ->
          %Tesla.Env{
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "ग्लिफ़िक त्वरित उत्तर का परीक्षण करें?"}
                ]
              }
            },
            status: 200
          }

        String.contains?(env.body, "Quick Reply Fixture") ->
          %Tesla.Env{
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "त्वरित उत्तर स्थिरता"}
                ]
              }
            },
            status: 200
          }

        String.contains?(env.body, "Test 1") ->
          %Tesla.Env{
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "परीक्षण 1"}
                ]
              }
            },
            status: 200
          }

        String.contains?(env.body, "Test 2") ->
          %Tesla.Env{
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "परीक्षण 2"}
                ]
              }
            },
            status: 200
          }

        String.contains?(env.body, "How was your experience with Glific?") ->
          %Tesla.Env{
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "ग्लिफ़िक त्वरित उत्तर का परीक्षण करें?"}
                ]
              }
            },
            status: 200
          }

        String.contains?(env.body, "Quick Reply Test Text 2") ->
          %Tesla.Env{
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "त्वरित उत्तर स्थिरता"}
                ]
              }
            },
            status: 200
          }

        String.contains?(env.body, "Great") ->
          %Tesla.Env{
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "उत्कृष्ट"}
                ]
              }
            },
            status: 200
          }

        String.contains?(env.body, "Awesome") ->
          %Tesla.Env{
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "शानदार"}
                ]
              }
            },
            status: 200
          }

        String.contains?(env.body, "please share your location") ->
          %Tesla.Env{
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "कृपया अपना स्थान साझा करें"}
                ]
              }
            },
            status: 200
          }

        String.contains?(env.body, "Glific Features") ->
          %Tesla.Env{
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "शानदार विशेषताएं"}
                ]
              }
            },
            status: 200
          }

        String.contains?(env.body, "Excitement level") ->
          %Tesla.Env{
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "उत्साह का स्तर"}
                ]
              }
            },
            status: 200
          }

        String.contains?(env.body, "glific") ->
          %Tesla.Env{
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "ग्लिफ़िक"}
                ]
              }
            },
            status: 200
          }

        String.contains?(env.body, "caption is footer") ->
          %Tesla.Env{
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "कैप्शन पाद लेख है"}
                ]
              }
            },
            status: 200
          }

        true ->
          %Tesla.Env{
            status: 200,
            body: %{
              "data" => %{
                "translations" => [
                  %{"translatedText" => "अनुवाद उपलब्ध नहीं है"}
                ]
              }
            }
          }
      end
    end)

    :ok
  end

  test "translate_interactive_template/1 translates an interactive",
       %{organization_id: _organization_id} = attrs do
    interactive = Fixtures.interactive_fixture(attrs)

    result = InteractiveTemplates.translate_interactive_template(interactive)

    assert {:ok, %InteractiveTemplate{translations: translations}, _message} = result

    assert Map.has_key?(translations, "2")
    assert translations["2"]["content"]["text"] == "ग्लिफ़िक त्वरित उत्तर का परीक्षण करें?"
    assert translations["2"]["content"]["header"] == "त्वरित उत्तर स्थिरता"
    assert Enum.any?(translations["2"]["options"], fn option -> option["title"] == "परीक्षण 1" end)
    assert Enum.any?(translations["2"]["options"], fn option -> option["title"] == "परीक्षण 2" end)

    # if url is present
    url_interactive =
      Fixtures.interactive_fixture(Map.merge(@valid_url_attrs, attrs))

    result = InteractiveTemplates.translate_interactive_template(url_interactive)

    assert {:ok, %InteractiveTemplate{translations: translations}, _message} = result

    assert translations == @valid_url_attrs[:translations]
  end

  test "export the interactive template when add translation is true",
       %{organization_id: _organization_id} = attrs do
    add_translation = true
    # type quick reply
    interactive =
      Fixtures.interactive_fixture(Map.merge(@valid_more_attrs, attrs))

    expected_export_data = """
    Attribute,en,hi
    Header,Quick Reply Test Text 2,त्वरित उत्तर स्थिरता
    Text,How was your experience with Glific?,ग्लिफ़िक त्वरित उत्तर का परीक्षण करें?
    OptionTitle 1,Great,उत्कृष्ट
    OptionTitle 2,Awesome,शानदार
    """

    {:ok, %{export_data: export_data}} =
      InteractiveTemplates.export_interactive_template(interactive, add_translation)

    assert String.trim(export_data) == String.trim(expected_export_data)

    # type location
    interactive =
      Fixtures.interactive_fixture(Map.merge(@valid_location_attrs, attrs))

    location_export_data = """
    Attribute,en,hi
    Body,please share your location,कृपया अपना स्थान साझा करें
    """

    {:ok, %{export_data: export_data}} =
      InteractiveTemplates.export_interactive_template(interactive, add_translation)

    assert String.trim(export_data) == String.trim(location_export_data)

    # type interactive
    interactive =
      Fixtures.interactive_fixture(Map.merge(@valid_list_attrs, attrs))

    list_export_data = """
    Attribute,en,hi
    Title,glific,ग्लिफ़िक
    Body,How was your experience with Glific?,ग्लिफ़िक त्वरित उत्तर का परीक्षण करें?
    GlobalButtonTitle,Glific Features,शानदार विशेषताएं
    ItemTitle 1,Excitement level,उत्साह का स्तर
    ItemSubtitle 1,Excitement level,उत्साह का स्तर
    OptionTitle 1.1,Great,उत्कृष्ट
    OptionDescription 1.1,Awesome,शानदार
    """

    {:ok, %{export_data: export_data}} =
      InteractiveTemplates.export_interactive_template(interactive, add_translation)

    export_data_trimmed =
      String.split(export_data, "\n")
      |> Enum.map_join("\n", &String.trim_trailing/1)

    assert String.trim(export_data_trimmed) == String.trim(list_export_data)

    # type quick reply with footer
    interactive =
      Fixtures.interactive_fixture(Map.merge(@valid_footer_attrs, attrs))

    expected_export_data = """
    Attribute,en,hi
    Footer,caption is footer,कैप्शन पाद लेख है
    Header,Glific Features,शानदार विशेषताएं
    Text,How was your experience with Glific?,ग्लिफ़िक त्वरित उत्तर का परीक्षण करें?
    OptionTitle 1,Great,उत्कृष्ट
    OptionTitle 2,Awesome,शानदार
    """

    {:ok, %{export_data: export_data}} =
      InteractiveTemplates.export_interactive_template(interactive, add_translation)

    assert String.trim(export_data) == String.trim(expected_export_data)
  end

  test "export the interactive template when add translation is false",
       %{organization_id: _organization_id} = attrs do
    add_translation = false

    interactive =
      Fixtures.interactive_fixture(Map.merge(@valid_list_attrs, attrs))

    list_export_data = """
    Attribute,en,hi
    Title,glific,
    Body,How was your experience with Glific?,
    GlobalButtonTitle,Glific Features,
    ItemTitle 1,Excitement level,
    ItemSubtitle 1,Excitement level,
    OptionTitle 1.1,Great,
    OptionDescription 1.1,Awesome,
    """

    {:ok, %{export_data: export_data}} =
      InteractiveTemplates.export_interactive_template(interactive, add_translation)

    assert String.trim(export_data) == String.trim(list_export_data)

    # type quick reply with footer
    interactive =
      Fixtures.interactive_fixture(Map.merge(@valid_footer_attrs, attrs))

    expected_export_data = """
    Attribute,en,hi
    Footer,caption is footer,
    Header,Glific Features,
    Text,How was your experience with Glific?,
    OptionTitle 1,Great,
    OptionTitle 2,Awesome,
    """

    {:ok, %{export_data: export_data}} =
      InteractiveTemplates.export_interactive_template(interactive, add_translation)

    assert String.trim(export_data) == String.trim(expected_export_data)
  end

  test "import the interactive template",
       %{organization_id: _organization_id} = attrs do
    # type list
    interactive =
      Fixtures.interactive_fixture(Map.merge(@valid_list_attrs, attrs))

    translated_data =
      [
        ["Attribute", "en", "hi"],
        ["Title", "glific", "ग्लिफ़िक"],
        ["Body", "How was your experience with Glific?", "ग्लिफ़िक त्वरित उत्तर का परीक्षण करें?"],
        ["GlobalButtonTitle", "Glific Features", "शानदार विशेषताएं"],
        ["ItemTitle 1", "Excitement level", "उत्साह का स्तर"],
        ["ItemSubtitle 1", "Excitement level", "उत्साह का स्तर"],
        ["OptionTitle 1.1", "Great", "उत्कृष्ट"],
        ["OptionDescription 1.1", "Awesome", "शानदार"]
      ]

    {:ok, imported_temp, _message} =
      InteractiveTemplates.import_interactive_template(translated_data, interactive)

    imported_translation = imported_temp.translations

    translation = @expected_list_attrs[:translations]

    assert imported_translation == translation

    # type quick reply with footer
    interactive =
      Fixtures.interactive_fixture(Map.merge(@valid_footer_attrs, attrs))

    translated_data = [
      ["Attribute", "en", "hi"],
      ["Footer", "caption is footer", "कैप्शन पाद लेख है"],
      ["Header", "Glific Features", "शानदार विशेषताएं"],
      ["Text", "How was your experience with Glific?", "ग्लिफ़िक त्वरित उत्तर का परीक्षण करें?"],
      ["OptionTitle 1", "Great", "उत्कृष्ट"],
      ["OptionTitle 2", "Awesome", "शानदार"]
    ]

    {:ok, imported_temp, _message} =
      InteractiveTemplates.import_interactive_template(translated_data, interactive)

    imported_translation = imported_temp.translations

    translation = @expected_footer_attrs[:translations]

    assert imported_translation == translation

    # type location
    interactive =
      Fixtures.interactive_fixture(Map.merge(@valid_location_attrs, attrs))

    translated_data = [
      ["Attribute", "en", "hi"],
      ["Action", "send_location", "send_location"],
      ["Body", "please share your location", "कृपया अपना स्थान साझा करें"]
    ]

    {:ok, imported_temp, _message} =
      InteractiveTemplates.import_interactive_template(translated_data, interactive)

    imported_translation = imported_temp.translations

    translation = @expected_location_attrs[:translations]

    assert imported_translation == translation
  end
end
