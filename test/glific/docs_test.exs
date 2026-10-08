defmodule Glific.DocsTest do
  @moduledoc "The entry point other code calls."

  use ExUnit.Case, async: true

  alias Glific.Docs

  setup_all do
    Docs.Index.warm()
    :ok
  end

  test "it reports how much documentation is indexed" do
    assert Docs.count() > 100
  end

  test "a question the documentation does not cover is an error, not an invented answer" do
    assert {:error, :no_context} = Docs.ask("zzzqqq unrelatedtoglific")
  end

  test "the same is true of the streaming entry point" do
    assert {:error, :no_context} = Docs.ask_stream("zzzqqq unrelatedtoglific")
  end
end
