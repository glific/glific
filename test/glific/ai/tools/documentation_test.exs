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
  alias Glific.AI.Tools.Documentation
  alias Glific.Docs
  alias Glific.Fixtures

  setup do
    Docs.warm()
    %{user: Fixtures.user_fixture(%{organization_id: 1})}
  end

  # The gateway opens a read-only transaction per call, which these do not
  # need: the search is in memory. One test below goes through it.
  defp search(query, limit \\ 5),
    do: Documentation.run("search_documentation", %{query: query, limit: limit})

  describe "what a search returns" do
    test "sections with the page they came from" do
      assert {:ok, [section | _rest]} = search("publish a flow")

      assert section.title != ""
      assert section.body != ""
      assert section.section =~ "›" or section.section == section.title
      assert is_nil(section.source) or section.source =~ ~r{^https?://}
    end

    test "sections rather than a composed answer" do
      # The skill writes the reply, so the tool returns the raw sections.
      {:ok, [section | _rest]} = search("opt-in")

      assert Map.has_key?(section, :body)
      refute Map.has_key?(section, :answer)
    end

    test "the number of sections is clamped" do
      assert {:ok, sections} = search("flow", 500)
      assert length(sections) <= 10
    end

    test "no single section can crowd out the others" do
      for section <- elem(search("flow", 10), 1) do
        assert byte_size(section.body) <= 2_100, section.title
      end
    end

    test "a query matching nothing is an error the model can act on" do
      assert {:error, message} = search("zzzqqq unrelatedtoglific")
      assert message =~ "Nothing in the documentation"
    end

    test "an off-topic question does not come back with sections anyway" do
      for question <- ["what is the weather in Mumbai today", "write me a poem about cats"] do
        assert {:error, _message} = search(question), question
      end
    end

    test "no engineering detail reaches an answer" do
      # An NGO told to call an internal API has been given a dead end. The
      # heading counts too — some sections cite a file only in the title.
      for section <- elem(search("gupshup wallet balance"), 1) do
        refute section.body =~ ~r/lib\/glific\/|\.ex:\d|defmodule/, section.title
        refute section.section =~ ~r/lib\/glific\/|\.ex:\d|defmodule/, section.title
      end
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

    test "each supported subject returns something" do
      for topic <- @topics, do: assert({:ok, [_ | _]} = search(topic), topic)
    end
  end

  describe "wiring" do
    test "the agent can reach it", %{user: user} do
      assert Documentation in Skills.modules(Knowledge)
      assert "search_documentation" in Enum.map(Tools.all(), & &1.name)

      assert {:ok, [_section | _rest]} =
               Tools.run("search_documentation", %{"query" => "publish a flow"}, user)
    end
  end
end
