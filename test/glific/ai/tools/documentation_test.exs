defmodule Glific.AI.Tools.DocumentationTest do
  @moduledoc """
  The documentation tool, and its wiring into the agent.

  Tolerant about wording — the corpus is prose that is meant to be edited, and
  asserting on a sentence would turn a documentation edit into a failing build.
  What is pinned is the shape of a result and the subjects the corpus covers.
  """

  use Glific.DataCase

  alias Glific.AI.{Skills, Tools}
  alias Glific.AI.Skills.Knowledge
  alias Glific.Docs
  alias Glific.Fixtures

  setup do
    Docs.Index.warm()
    %{user: Fixtures.user_fixture(%{organization_id: 1})}
  end

  describe "the tool" do
    test "a search returns sections with the page they came from", %{user: user} do
      assert {:ok, [section | _rest]} =
               Tools.run("search_documentation", %{"query" => "publish a flow"}, user)

      assert section.title != ""
      assert section.body != ""
      assert section.section =~ "›" or section.section == section.title
      assert is_nil(section.source) or section.source =~ ~r{^https?://}
    end

    test "the number of sections is clamped", %{user: user} do
      assert {:ok, sections} =
               Tools.run("search_documentation", %{"query" => "flow", "limit" => 500}, user)

      assert length(sections) <= 10
    end

    test "a query matching nothing is an error the model can act on", %{user: user} do
      # Both legs have to come back empty for this: the lexical one because no
      # term matches, the semantic one because nothing clears the floor.
      assert {:error, message} =
               Tools.run("search_documentation", %{"query" => "zzzqqq unrelatedtoglific"}, user)

      assert message =~ "Nothing in the documentation"
    end

    test "an off-topic question does not come back with sections anyway", %{user: user} do
      for question <- ["what is the weather in Mumbai today", "write me a poem about cats"] do
        assert {:error, _message} =
                 Tools.run("search_documentation", %{"query" => question}, user),
               question
      end
    end

    test "it returns sections rather than a composed answer", %{user: user} do
      # The skill writes the reply, so the tool returns the raw sections.
      {:ok, [section | _rest]} = Tools.run("search_documentation", %{"query" => "opt-in"}, user)

      assert Map.has_key?(section, :body)
      refute Map.has_key?(section, :answer)
    end
  end

  describe "subjects the corpus must cover" do
    @topics [
      "how do I publish a flow",
      "opt-in and opt-out",
      "HSM template approval",
      "webhook call from a flow",
      "google sheet integration",
      "collections and contact fields"
    ]

    test "each supported subject returns something", %{user: user} do
      for topic <- @topics do
        assert {:ok, [_ | _]} = Tools.run("search_documentation", %{"query" => topic}, user),
               topic
      end
    end
  end

  describe "wiring" do
    test "the knowledge skill can reach it" do
      assert Glific.AI.Tools.Documentation in Skills.modules(Knowledge)
    end

    test "it is registered with the agent" do
      assert "search_documentation" in Enum.map(Tools.all(), & &1.name)
    end

    test "no engineering detail reaches an answer", %{user: user} do
      # An NGO told to call an internal API has been given a dead end.
      {:ok, sections} =
        Tools.run("search_documentation", %{"query" => "gupshup wallet balance"}, user)

      for section <- sections do
        # The heading counts too — some sections cite a file only in the title.
        refute section.body =~ ~r/lib\/glific\/|\.ex:\d|defmodule/, section.title
        refute section.section =~ ~r/lib\/glific\/|\.ex:\d|defmodule/, section.title
      end
    end
  end
end
