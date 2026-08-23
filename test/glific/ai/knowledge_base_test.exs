defmodule Glific.AI.KnowledgeBaseTest do
  use ExUnit.Case, async: true

  alias Glific.AI.KnowledgeBase

  describe "content/0" do
    test "is a non-empty binary" do
      assert is_binary(KnowledgeBase.content())
      assert KnowledgeBase.content() != ""
    end

    test "returns the same value on repeated calls" do
      assert KnowledgeBase.content() == KnowledgeBase.content()
    end

    test "documents the core Glific concepts staff ask about" do
      content = KnowledgeBase.content()

      assert content =~ "## What is a flow?"
      assert content =~ "## HSM / templates and Meta approval"
      assert content =~ "## Opt-in and opt-out"
      assert content =~ "## Collections"
      assert content =~ "## Contact stuck in a flow"
      assert content =~ "## BSP and Gupshup"
      assert content =~ "24-hour"
    end
  end

  describe "byte_size/0" do
    test "matches the actual content size and is substantial" do
      assert KnowledgeBase.byte_size() == byte_size(KnowledgeBase.content())
      assert KnowledgeBase.byte_size() > 1_000
    end
  end
end
