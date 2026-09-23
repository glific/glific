defmodule Glific.AI.DocumentationRankingTest do
  @moduledoc """
  Ranking behaviour, measured against a fixture corpus.

  The shipped documents are prose and are meant to be edited; asserting on their
  wording here would mean an edit to a sentence breaks the ranker's tests for a
  reason that has nothing to do with ranking. The fixtures exist to be stable,
  and to make the constants — the heading weight, the score floor, the tie
  break — visible to anyone who changes them.
  """

  use ExUnit.Case, async: true

  alias Glific.AI.Documentation

  @documents [{"ranking_guide", "Ranking Guide"}, {"second_manual", "Second Manual"}]

  setup_all do
    directory = Path.join([__DIR__, "..", "..", "support", "fixtures", "documentation"])
    %{index: Documentation.build(@documents, Path.expand(directory))}
  end

  defp titles(index, query, limit \\ 3) do
    index |> Documentation.search_in(query, limit) |> Enum.map(& &1.title)
  end

  defp top(index, query), do: index |> titles(query, 1) |> List.first()

  describe "the body cap" do
    test "a multibyte character straddling the cap does not yield invalid UTF-8" do
      # The cap is counted in bytes. A section built so that a 3-byte character
      # begins two bytes before the cap would, on a raw byte slice, come back
      # with two thirds of that character - which is not valid UTF-8, and which
      # `Jason.encode/1` refuses. A JSON-encodable result is what
      # `Glific.AI.Tool` promises its caller.
      filler = String.duplicate("truncation sentinel body text padding ", 30)
      pad = 1498 - byte_size(filler)
      body = filler <> String.duplicate("x", pad) <> "\u2194" <> " tail"

      directory = Path.join(System.tmp_dir!(), "doc_cap_#{System.unique_integer([:positive])}")
      File.mkdir_p!(directory)
      on_exit(fn -> File.rm_rf!(directory) end)
      File.write!(Path.join(directory, "capped.md"), "## Capped section\n\n" <> body)

      [section] =
        [{"capped", "Capped"}]
        |> Documentation.build(directory)
        |> Documentation.search_in("capped truncation sentinel", 1)

      assert section.truncated
      assert String.valid?(section.body), "a byte slice cut the multibyte character in half"
      assert {:ok, _json} = Jason.encode(section)
    end
  end

  describe "the corpus is read as expected" do
    test "every fixture section is indexed", %{index: index} do
      assert length(index) >= 9
    end

    test "a fenced comment is not a heading", %{index: index} do
      # Without fence tracking the `#` in the bash block would start a section
      # and orphan the text below it.
      refute Enum.any?(index, &(&1.title =~ "shell comment"))

      # The text after the fence must still belong to the section, not to a
      # section invented from the comment line.
      section = Enum.find(index, &(&1.title == "Section with a fenced comment"))
      assert section.body =~ "sentinelaardvark"
    end

    test "a subsection inherits the source url of the page above it", %{index: index} do
      section = Enum.find(index, &(&1.title == "Limits and constraints"))
      assert section.url == "https://example.test/docs/ranking-guide/"
    end
  end

  describe "the heading weight" do
    test "a heading match outranks the same term in a body", %{index: index} do
      # Both sections are about opt-in; only one says so in its heading. Drop
      # @heading_weight to 1 and the body-heavy section wins instead.
      assert top(index, "opt-in") == "Opt-in lifecycle"
    end

    test "a three-letter topic still reaches its heading", %{index: index} do
      # opt, otp, api, gcs, hsm are all topics people search for. A length guard
      # on the whole-word branch makes every one of them invisible.
      for term <- ~w(otp api gcs) do
        assert top(index, term <> " setup") == "OTP and API and GCS", term
      end
    end

    test "hsm reaches the HSM section rather than the general one", %{index: index} do
      assert top(index, "hsm limit") == "Common HSM template errors"
    end
  end

  describe "the score floor" do
    test "a section sharing one ordinary word is not a result", %{index: index} do
      assert Documentation.search_in(index, "the", 5) == []
    end

    test "a lone body word does not clear the floor", %{index: index} do
      # "buttons" appears in one body and no heading, so it scores 1. Lower
      # @minimum_score and coincidental matches like this become results.
      assert Documentation.search_in(index, "buttons", 5) == []
    end

    test "an off-topic question returns nothing rather than the closest thing", %{index: index} do
      assert Documentation.search_in(index, "who won the world cup in 1998", 5) == []
    end

    test "a single heading match is enough to clear the floor", %{index: index} do
      # One heading match scores @heading_weight, which must stay above
      # @minimum_score or a precise one-word question returns nothing.
      assert top(index, "otp") == "OTP and API and GCS"
    end
  end

  describe "the tie break" do
    test "the shorter of two equally scoring sections comes first", %{index: index} do
      # Both headings carry webhook and timeout, so the scores are identical and
      # the heading counts are identical. The longer section is read first
      # because its file sorts first, so only the tie break can decide this.
      assert top(index, "webhook timeout") == "Webhook timeout handling"
    end

    test "results are ordered, not merely present", %{index: index} do
      assert titles(index, "hsm template error") |> List.first() ==
               "Common HSM template errors"
    end
  end

  describe "notation" do
    test "a placeholder in the question reaches the heading that uses it", %{index: index} do
      assert top(index, "@results.category") == "Using @results.category in a flow"
    end

    test "a short fragment does not match a heading by substring", %{index: index} do
      # `.in` would be contained in several headings; only whole words count.
      assert Documentation.search_in(index, ".in", 5) == []
    end
  end

  describe "what a result carries" do
    test "a long body is capped and says so", %{index: index} do
      section =
        index
        |> Documentation.search_in("webhook timeout", 5)
        |> Enum.find(&(&1.title == "Webhook timeout reference"))

      assert byte_size(section.body) <= 1_500
      assert section.truncated
      assert section.of > 1_500
    end

    test "a body within the cap is returned whole", %{index: index} do
      section =
        index
        |> Documentation.search_in("webhook timeout", 5)
        |> Enum.find(&(&1.title == "Webhook timeout handling"))

      refute Map.has_key?(section, :truncated)
    end

    test "the filename never reaches the model", %{index: index} do
      for section <- Documentation.search_in(index, "opt-in", 5) do
        refute Map.has_key?(section, :document)
        assert Map.has_key?(section, :path)
      end
    end
  end
end
