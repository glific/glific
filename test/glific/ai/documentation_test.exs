defmodule Glific.AI.DocumentationTest do
  use Glific.DataCase

  alias Glific.AI.{Documentation, Skills, Tools}
  alias Glific.AI.Skills.Knowledge
  alias Glific.Fixtures

  describe "searching the documentation" do
    test "the corpus is indexed" do
      assert Documentation.count() > 100
    end

    test "a question in Glific's own words finds the section that answers it" do
      titles =
        "save a user's response so I can use it later in the flow"
        |> Documentation.search(3)
        |> Enum.map(& &1.title)

      assert Enum.any?(titles, &(&1 =~ "save a user's response"))
    end

    test "a heading match rescues notation the documents only write as a placeholder" do
      # The documents write `@results.<name>`, so the literal `@results.input`
      # appears in no section body. The heading does contain `.input`.
      titles =
        "@results.input vs @results.category"
        |> Documentation.search(3)
        |> Enum.map(& &1.title)

      assert Enum.any?(titles, &(&1 =~ ".input"))
    end

    test "results carry the page they came from, so an answer can cite it" do
      assert [_ | _] = sections = Documentation.search("wait for response node", 5)
      assert Enum.any?(sections, &(&1.url =~ "https://"))
      assert Enum.all?(sections, &(&1.document != ""))
    end

    test "the limit is honoured" do
      assert length(Documentation.search("flow", 2)) == 2
    end

    test "nothing matching comes back empty rather than as noise" do
      assert Documentation.search("zzzqqq unrelatedtoglific", 5) == []
    end

    test "a message with no topic in it returns nothing, not a plausible section" do
      for message <- [
            "thanks!",
            "got it, thank you so much for your help",
            "can you explain that more?"
          ] do
        assert Documentation.search(message, 3) == [], "#{message} should not match"
      end
    end

    test "an off-topic question scores below the floor" do
      assert Documentation.search("what's the weather like in Mumbai today?", 3) == []
    end

    test "a word ending a sentence is indexed without its full stop" do
      # "...published flow." must be reachable as "flow", not only as "flow."
      assert Documentation.search("flow.", 3) == Documentation.search("flow", 3)
    end

    test "a plain word must be a word of the heading, not a fragment of one" do
      titles = "ignore" |> Documentation.search(5) |> Enum.map(& &1.title)

      refute Enum.any?(titles, &(&1 =~ "ignore_keywords"))
    end

    test "a singular in the question reaches a plural in the heading" do
      titles = "HSM template error sending" |> Documentation.search(3) |> Enum.map(& &1.title)

      assert Enum.any?(titles, &(&1 =~ "HSM Template Errors"))
    end

    test "a subsection inherits the source url of the page above it" do
      # "Screen: Flow list" carries no `Source:` line of its own; the "Flows"
      # page above it does, and that is what an answer has to cite.
      assert [section | _] =
               "Screen: Flow list"
               |> Documentation.search(3)
               |> Enum.filter(&(&1.title =~ "Flow list"))

      assert section.url =~ "https://"
    end
  end

  describe "the tool" do
    setup do
      %{user: Fixtures.user_fixture(%{organization_id: 1})}
    end

    test "returns sections for a query", %{user: user} do
      assert {:ok, [section | _]} =
               Tools.run("search_documentation", %{"query" => "collection"}, user)

      assert is_binary(section.title)
      assert is_binary(section.body)
    end

    test "a query matching nothing is an error the model can act on", %{user: user} do
      assert {:error, message} =
               Tools.run("search_documentation", %{"query" => "zzzqqq unrelatedtoglific"}, user)

      assert message =~ "Glific's own terms"
    end

    test "the limit is clamped so one search cannot flood the context", %{user: user} do
      assert {:ok, sections} =
               Tools.run("search_documentation", %{"query" => "flow", "limit" => 50}, user)

      assert length(sections) <= 10
    end
  end

  describe "the skill that owns it" do
    test "the documentation is searchable from the skill that answers questions" do
      names = Knowledge |> Skills.tools() |> Enum.map(& &1.name)

      assert "search_documentation" in names
    end

    test "there is no separate documentation skill to route to" do
      assert {:error, _} = Skills.fetch("documentation")
    end

    test "how the tool is called is documented on the tool, not per skill" do
      # A skill that gains the tool later — a debug skill — inherits the
      # vocabulary guidance instead of repeating it.
      [spec] = Tools.all([Glific.AI.Tools.Documentation])

      assert spec.description =~ "translate first"
      refute Knowledge.prompt() =~ "a programme, a campaign"
    end
  end
end
