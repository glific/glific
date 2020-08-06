defmodule Glific.Flows.MessageVarParserTest do
  use Glific.DataCase, async: true

  alias Glific.Contacts
  alias Glific.Flows.MessageVarParser

  test "parse/2 will parse the string with variable" do
    # binding with 1 dots will replace the variable
    parsed_test =
      MessageVarParser.parse("hello @contact.name", %{"contact" => %{"name" => "Glific"}})

    MessageVarParser.parse("hello @organization.name", %{"organization" => %{"name" => "Glific"}})

    assert parsed_test == "hello Glific"

    # binding with 2 dots will replace the variable
    parsed_test =
      MessageVarParser.parse("hello @contact.fileds.name", %{
        "contact" => %{"fileds" => %{"name" => "Glific"}}
      })

    assert parsed_test == "hello Glific"

    # if variable is not defined then it won't effect the input
    parsed_test =
      MessageVarParser.parse("hello @contact.fileds.name", %{
        "results" => %{"fileds" => %{"name" => "Glific"}}
      })

    assert parsed_test == "hello @contact.fileds.name"

    # atom keys will be convert into string automatically
    parsed_test = MessageVarParser.parse("hello @contact.name", %{"contact" => %{name: "Glific"}})

    assert parsed_test == "hello Glific"

    [contact | _tail] = Contacts.list_contacts()
    contact = Map.from_struct(contact)
    parsed_test = MessageVarParser.parse("hello @contact.name", %{"contact" => contact})
    assert parsed_test == "hello #{contact.name}"

    [contact | _tail] = Contacts.list_contacts()

    {:ok, contact} =
      Contacts.update_contact(contact, %{
        fields: %{
          "name" => %{
            "type" => "string",
            "value" => "Glific Contact",
            "inserted_at" => "2020-08-04"
          },
          "age" => %{
            "type" => "string",
            "value" => "20",
            "inserted_at" => "2020-08-04"
          }
        }
      })

    contact = Map.from_struct(contact)

    parsed_test =
      MessageVarParser.parse(
        "hello @contact.fields.name, your age is @contact.fields.age years.",
        %{"contact" => contact}
      )

    assert parsed_test == "hello Glific Contact, your age is 20 years."
  end
end
