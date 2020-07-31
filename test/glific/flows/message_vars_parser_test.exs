defmodule Glific.Flows.MessageVarParserTest do
  use Glific.DataCase, async: true

  alias Glific.Contacts
  alias Glific.Flows.MessageVarParser

  test "parse/2 will parse the string with variable" do
    # binding with 1 dots will replace the variable
    parsed_test =
      MessageVarParser.parse("hello @contact.name", %{"contact" => %{"name" => "Glific"}})

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
  end
end
