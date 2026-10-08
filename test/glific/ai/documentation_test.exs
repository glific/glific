defmodule Glific.AI.DocumentationTest do
  @moduledoc """
  The shipped corpus, and the tool and skill that reach it.

  Deliberately tolerant about wording: the documents are prose and are meant to
  be edited, so an assertion on a sentence would turn a documentation edit into
  a failing build. Ranking behaviour is measured against a fixture corpus in
  `Glific.AI.DocumentationRankingTest`, where the text is stable on purpose.
  """

  use Glific.DataCase

  alias Glific.AI.{Documentation, Skills, Tools}
  alias Glific.AI.Skills.Knowledge
  alias Glific.Fixtures

  describe "the shipped corpus" do
    test "every document in the manifest contributes sections" do
      assert Documentation.count() > 100
    end

    test "every section carries a title and a trail" do
      for section <- Documentation.search("flow", 10) do
        assert section.title != ""
        assert section.path =~ "›" or section.path == section.title
      end
    end

    test "sections carry the page they came from, so an answer can cite it" do
      sections =
        ["publish a flow", "hsm template", "opt-in", "webhook"]
        |> Enum.flat_map(&Documentation.search(&1, 5))

      assert Enum.any?(sections, &(not is_nil(&1.url)))
      assert Enum.all?(sections, &(is_nil(&1.url) or &1.url =~ ~r{^https?://}))
    end

    test "no body exceeds the cap, however long the source section is" do
      for query <- ["flow", "template", "webhook", "contact", "message"],
          section <- Documentation.search(query, 10) do
        assert byte_size(section.body) <= 1_500, section.title
      end
    end

    test "the filename never reaches the model" do
      for section <- Documentation.search("flow", 5) do
        refute Map.has_key?(section, :document)
      end
    end
  end

  describe "questions the corpus should answer" do
    # Topic-level, not wording-level: each of these is a support subject the
    # corpus is expected to cover at all. Rewording a section is fine; losing
    # the subject is not.
    @topics [
      "how do I publish a flow",
      "opt-in and opt-out",
      "HSM template approval",
      "webhook call from a flow",
      "google sheet integration",
      "collections and contact fields"
    ]

    test "each supported subject returns something" do
      for topic <- @topics do
        assert Documentation.search(topic, 3) != [], topic
      end
    end

    test "a complaint reaches the diagnose playbook" do
      for complaint <- [
            "my flow is not running",
            "contact did not receive the message",
            "webhook not firing",
            "broadcast did not reach the collection"
          ] do
        paths = complaint |> Documentation.search(2) |> Enum.map(& &1.path)
        assert Enum.any?(paths, &(&1 =~ "Diagnose Playbook")), complaint
      end
    end

    test "a message with no topic in it returns nothing, not a plausible section" do
      for message <- [
            "zzzqqq unrelatedtoglific",
            "what's the weather like in Mumbai today?",
            "thanks, that worked!"
          ] do
        assert Documentation.search(message, 3) == [], "#{message} should not match"
      end
    end
  end

  describe "the tool" do
    setup do
      %{user: Fixtures.user_fixture(%{organization_id: 1})}
    end

    test "returns sections for a query", %{user: user} do
      assert {:ok, sections} =
               Tools.run("search_documentation", %{"query" => "publish a flow"}, user)

      assert [%{title: _, body: _} | _] = sections
    end

    test "a query matching nothing is an error the model can act on", %{user: user} do
      assert {:error, message} =
               Tools.run("search_documentation", %{"query" => "zzzqqq unrelatedtoglific"}, user)

      assert message != ""
    end

    test "the limit is clamped so one search cannot flood the context", %{user: user} do
      assert {:ok, sections} =
               Tools.run("search_documentation", %{"query" => "flow", "limit" => 500}, user)

      assert length(sections) <= 10
    end

    test "it holds no database connection", %{user: user} do
      # The search is in-memory. Opening the gateway's read-only transaction for
      # it would take a pooled connection for work that issues no SQL.
      refute Glific.AI.Tools.Documentation.reads_database?()
      assert {:ok, _} = Tools.run("search_documentation", %{"query" => "flow"}, user)
    end
  end

  describe "the skill that owns it" do
    test "the documentation is searchable from the skill that answers questions" do
      assert Glific.AI.Tools.Documentation in Skills.modules(Knowledge)
    end

    test "there is no separate documentation skill to route to" do
      names = Enum.map(Skills.all(), & &1.name())
      refute "documentation" in names
    end

    test "how the tool is called is documented on the tool, not per skill" do
      [spec] = Glific.AI.Tools.Documentation.specs()

      assert spec.description =~ "translate"
      assert spec.description =~ "collection"
    end
  end
end
