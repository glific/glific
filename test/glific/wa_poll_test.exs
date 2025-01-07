defmodule Glific.WAPollTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.WaPoll

  describe "create_wa_poll/1" do
    @valid_attrs %{
      label: "Test Poll",
      organization_id: 1,
      only_one: true,
      poll_content: %{
        "options" => [
          %{"id" => 0, "name" => "Option 1", "voters" => [], "votes" => 0},
          %{"id" => 1, "name" => "Option 2", "voters" => [], "votes" => 0}
        ],
        "text" => "Poll question?"
      }
    }

    test "successfully creates a poll with valid attributes" do
      assert {:ok, poll} = WaPoll.create_wa_poll(@valid_attrs)
      assert poll.label == "Test Poll"
      assert poll.poll_content["text"] == "Poll question?"
    end

    test "fails when options exceed the limit of 12" do
      attrs =
        Map.put(@valid_attrs, :poll_content, %{
          "options" =>
            Enum.map(0..12, fn id ->
              %{"id" => id, "name" => "Option #{id}", "voters" => [], "votes" => 0}
            end),
          "text" => "Poll with too many options"
        })

      assert {:error, message} = WaPoll.create_wa_poll(attrs)
      assert message == "The number of options should be up to 12 only, but got 13."
    end

    test "fails when duplicate option names are present" do
      attrs =
        Map.put(@valid_attrs, :poll_content, %{
          "options" => [
            %{"id" => 0, "name" => "Duplicate Option", "voters" => [], "votes" => 0},
            %{"id" => 1, "name" => "Duplicate Option", "voters" => [], "votes" => 0}
          ],
          "text" => "Poll with duplicate options"
        })

      assert {:error, message} = WaPoll.create_wa_poll(attrs)
      assert message == "Duplicate options detected: Duplicate Option."
    end
  end
end
