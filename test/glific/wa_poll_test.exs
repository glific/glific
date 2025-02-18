defmodule Glific.WAPollTest do
  alias Glific.Fixtures
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.WaPoll

  describe "create_wa_poll/1" do
    @valid_attrs %{
      label: "Test Poll",
      organization_id: 1,
      allow_multiple_answer: true,
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
      assert message == "Duplicate options detected"
    end

    test "fails when exceeds the character limit" do
      # the option should not contains more than 100 chars
      attrs =
        Map.put(@valid_attrs, :poll_content, %{
          "options" => [
            %{"id" => 0, "name" => String.duplicate("A", 102), "voters" => [], "votes" => 0},
            %{"id" => 1, "name" => "Duplicate Option", "voters" => [], "votes" => 0},
            %{
              "id" => 2,
              "name" =>
                "What happens when a fuzzy friend tries to get inside a book that's not meant to have pictures? The author and character have a fun battle",
              "voters" => [],
              "votes" => 0
            }
          ],
          "text" => "Poll with duplicate options"
        })

      assert {:error, message} = WaPoll.create_wa_poll(attrs)

      assert message ==
               "The following poll options exceed 100 characters: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA, What happens when a fuzzy friend tries to get inside a book that's not meant to have pictures? The author and character have a fun battle"

      # the body content should not be more than 255 chars
      attrs =
        Map.put(@valid_attrs, :poll_content, %{
          "options" => [
            %{
              "id" => 0,
              "name" => "What happens when a fuzzy friend tries to get inside a book",
              "voters" => [],
              "votes" => 0
            },
            %{"id" => 1, "name" => "Duplicate Option", "voters" => [], "votes" => 0}
          ],
          "text" => String.duplicate("A", 257)
        })

      assert {:error, message} = WaPoll.create_wa_poll(attrs)

      assert message == "The body characters should be up to 255 only, but got 257."
    end

    test "copy_wa_poll/2 fails when exceeds the character limit" do
      wa_poll = Fixtures.wa_poll_fixture()
      # the option should not contains more than 100 chars
      attrs =
        Map.put(@valid_attrs, :poll_content, %{
          "options" => [
            %{"id" => 0, "name" => String.duplicate("A", 102), "voters" => [], "votes" => 0},
            %{"id" => 1, "name" => "Duplicate Option", "voters" => [], "votes" => 0},
            %{
              "id" => 2,
              "name" =>
                "What happens when a fuzzy friend tries to get inside a book that's not meant to have pictures? The author and character have a fun battle",
              "voters" => [],
              "votes" => 0
            }
          ],
          "text" => "Poll with duplicate options"
        })

      assert {:error, message} = WaPoll.copy_wa_poll(wa_poll, attrs)

      assert message ==
               "The following poll options exceed 100 characters: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA, What happens when a fuzzy friend tries to get inside a book that's not meant to have pictures? The author and character have a fun battle"

      # the body content should not be more than 255 chars
      attrs =
        Map.put(@valid_attrs, :poll_content, %{
          "options" => [
            %{
              "id" => 0,
              "name" => "What happens when a fuzzy friend tries to get inside a book",
              "voters" => [],
              "votes" => 0
            },
            %{"id" => 1, "name" => "Duplicate Option", "voters" => [], "votes" => 0}
          ],
          "text" => String.duplicate("A", 257)
        })

      assert {:error, message} = WaPoll.copy_wa_poll(wa_poll, attrs)

      assert message == "The body characters should be up to 255 only, but got 257."
    end
  end
end
