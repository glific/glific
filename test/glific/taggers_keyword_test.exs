defmodule Glific.TaggersKeywordTest do
  use Glific.DataCase, async: false

  alias Glific.{
    Messages.Message,
    Seeds.SeedsDev,
    Taggers.Keyword
  }

  setup do
    SeedsDev.seed_tag()
    :ok
  end

  # and some random ordinals, hindi numbers, and emojis
  @checker ["hey", "hello", "goodbye", "thanks", "hindi", "english"]

  @checker_punct [
    "   hey %^$#&$^",
    "$#%^&$hello$%#^",
    "  bye "
  ]

  @invalid [
    "23",
    "आठ and more",
    "hundred",
    "some gibberirsh",
    "hello with some text",
    "bye with more text",
    "and  a thank you in the middle"
  ]

  test "ensure keyword maps has got some of the most common english (and soon hindi) phrases" do
    keyword_map = Keyword.get_keyword_map()

    Enum.map(
      @checker,
      fn v -> assert Map.get(keyword_map, v) > 0 end
    )
  end

  test "check keyword tag body matches things in keyword map, and skips non matches" do
    keyword_map = Keyword.get_keyword_map()

    Enum.map(
      @checker,
      fn v -> assert elem(Keyword.tag_body(v, keyword_map), 0) == :ok end
    )

    Enum.map(
      @invalid,
      fn v -> assert Keyword.tag_body(v, keyword_map) == :error end
    )
  end

  test "check keyword tag message matches things in keyword map, and skips non matches" do
    keyword_map = Keyword.get_keyword_map()

    Enum.map(
      @checker,
      fn v ->
        assert elem(Keyword.tag_message(%Message{body: v}, keyword_map), 0) == :ok
      end
    )

    Enum.map(
      @checker_punct,
      fn v ->
        assert elem(Keyword.tag_message(%Message{body: v}, keyword_map), 0) == :ok
      end
    )

    Enum.map(
      @invalid,
      fn v -> assert Keyword.tag_message(%Message{body: v}, keyword_map) == :error end
    )
  end
end
