defmodule GlificWeb.Schema.Middleware.PutSubscriberOrganizationTest do
  use GlificWeb.ConnCase

  alias Absinthe.Subscription.Local
  alias Glific.Fixtures

  @sent_message """
  subscription($organizationId: ID!) {
    sentMessage(organizationId: $organizationId) {
      id
      sendBy
    }
  }
  """

  test "a sent message resolves for a subscriber when published from a process without an organization",
       %{manager: user} do
    flow = Fixtures.flow_fixture(%{name: "Registration"})
    message = Fixtures.message_fixture(%{flow: :outbound, flow_id: flow.id})

    {:ok, %{"subscribed" => topic}} =
      Absinthe.run(@sent_message, GlificWeb.Schema,
        context: %{pubsub: GlificWeb.Endpoint, current_user: user},
        variables: %{"organizationId" => to_string(user.organization_id)}
      )

    GlificWeb.Endpoint.subscribe(topic)

    fn ->
      Local.publish_mutation(GlificWeb.Endpoint, message,
        sent_message: to_string(user.organization_id)
      )
    end
    |> Task.async()
    |> Task.await()

    message_id = to_string(message.id)

    assert_receive %Phoenix.Socket.Broadcast{
      event: "subscription:data",
      payload: %{
        result: %{
          data: %{"sentMessage" => %{"id" => ^message_id, "sendBy" => "Flow: Registration"}}
        }
      }
    }
  end
end
