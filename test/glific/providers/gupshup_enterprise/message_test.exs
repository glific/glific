defmodule Glific.Providers.Gupshup.Enterprise.MessageTest do
  use Glific.DataCase

  alias Glific.{
    Contacts.Contact,
    Messages.Message,
    Providers.Gupshup.Enterprise
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

    assert {:error, :no_phone} == Enterprise.Message.send_text(message)
  end
end
