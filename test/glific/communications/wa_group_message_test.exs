defmodule Glific.Communications.GroupMessageTest do
  use Glific.DataCase

  alias Glific.Communications.GroupMessage

  describe "receive_reaction_msg/2" do
    test "drops a reaction whose reactor id carries no phone", %{organization_id: organization_id} do
      for reactor_id <- [nil, "", "@c.us", 919_876_543_210] do
        assert {:error, "Reaction has no reactor id"} ==
                 GroupMessage.receive_reaction_msg(
                   %{"reactorId" => reactor_id, "reaction" => "👍", "msgId" => "m1"},
                   organization_id
                 )
      end
    end

    test "drops a reaction with no reactor id at all", %{organization_id: organization_id} do
      assert {:error, "Reaction has no reactor id"} ==
               GroupMessage.receive_reaction_msg(%{"reaction" => "👍"}, organization_id)
    end
  end
end
