defmodule Glific.Providers.Gupshup.MessageTest do
  use Glific.DataCase

  alias Glific.{
    Contacts.Contact,
    Messages.Message,
    Providers.Gupshup
  }

  test "send_text/2 refuses a receiver without a phone instead of calling the BSP",
       %{organization_id: organization_id} do
    message = %Message{
      body: "hello",
      is_hsm: false,
      uuid: Ecto.UUID.generate(),
      organization_id: organization_id,
      receiver: %Contact{phone: nil}
    }

    assert {:error, "Contact has no WhatsApp number."} == Gupshup.Message.send_text(message)
  end
end
