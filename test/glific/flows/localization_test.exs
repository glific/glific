defmodule Glific.Flows.LocalizationTest do
  use Glific.DataCase, async: true

  alias Glific.{
    Flows.Localization,
    Settings
  }

  test "process extracts the right values from json" do
    json = %{
      "hi" => %{
        "0ada0126-b6fc-4cc6-a17b-70cf5ba461d9" => %{
          "text" => [
            "अब आपकी भाषा @contact.language पर सेट है"
          ]
        }
      }
    }

    localization = Localization.process(json)

    assert get_in(localization.localizations, [
             "hi",
             "0ada0126-b6fc-4cc6-a17b-70cf5ba461d9",
             :text
           ]) ==
             "अब आपकी भाषा @contact.language पर सेट है"

    json = %{
      "hi" => %{
        "e46cc6ef-d037-4569-8fbe-64b4767c7734" => %{
          "text" => [
            "HINDI: Thank you for signing up with us @contact.fields.name Your age group is @contact.fields.age_group\n"
          ]
        },
        "0cde79fb-bff8-4ed2-ac99-135ea3403dbb" => %{
          "text" => [
            "HINDI: Sorry, we didn't understand that, please answer with a number 1-4.\n"
          ]
        },
        "e0171377-de7e-42ed-adbf-7c46da94a51c" => %{
          "text" => [
            "HINDI: Tell us your full name\n"
          ]
        }
      }
    }

    localization = Localization.process(json)
    assert length(Map.keys(get_in(localization.localizations, ["hi"]))) == 3
  end

  test "localization struct will be generated via embedded schema having localizations" do
    language_map = Settings.locale_id_map()
    localization = %Localization{localizations: language_map}
    assert localization.localizations == language_map

    localization = Localization.process(nil)
    assert localization.localizations == language_map
  end

  test "handle other edge cases with empty values" do
    empty_node_uuid = "0cde79fb-bff8-4ed2-ac99-135ea3403dbb"

    json = %{
      "hi" => %{
        "e46cc6ef-d037-4569-8fbe-64b4767c7734" => %{
          "text" => [
            "HINDI: Thank you for signing up with us @contact.fields.name Your age group is @contact.fields.age_group\n"
          ]
        },
        empty_node_uuid => %{},
        "e0171377-de7e-42ed-adbf-7c46da94a51c" => %{
          "text" => [
            "HINDI: Tell us your full name\n"
          ]
        }
      },
      "en" => nil
    }

    localization = Localization.process(json)
    localizations = localization.localizations
    assert localizations["hi"][empty_node_uuid] == nil
    assert localizations["en"] == %{}
  end

  test "attachment will also be processed" do
    attachment_node_uuid = "e46cc6ef-d037-4569-8fbe-64b4767c7734"

    json = %{
      "hi" => %{
        attachment_node_uuid => %{
          "attachments" => [
            "image:https://gliic.org/someimage.png"
          ]
        },
        "e0171377-de7e-42ed-adbf-7c46da94a51c" => %{
          "text" => [
            "HINDI: Tell us your full name\n"
          ]
        }
      },
      "en" => nil
    }

    localization = Localization.process(json)

    assert get_in(localization.localizations, ["hi", attachment_node_uuid]).attachments == %{
             "image" => "https://gliic.org/someimage.png"
           }
  end
end
