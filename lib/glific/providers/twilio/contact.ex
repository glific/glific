defmodule Glific.Communications.BSP.Twilio.Contact do
  @behaviour Glific.Communications.ContactBehaviour

  @impl Glific.Communications.ContactBehaviour
  def status(_args) do
    {:ok, :status}
  end
end
