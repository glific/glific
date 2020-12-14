defmodule Glific.Flows.LocalizationTest do
  use Glific.DataCase, async: true

  alias Glific.Flows.Localization

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

    assert get_in(localization.localizations, ["hi", "0ada0126-b6fc-4cc6-a17b-70cf5ba461d9", :text]) ==
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
end
