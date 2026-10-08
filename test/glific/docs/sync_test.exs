defmodule Glific.Docs.SyncTest do
  @moduledoc """
  Copying the documentation in from the repository it is written in.

  Served by a stub plug rather than by GitHub, so these do not reach the
  network. The documents are restored afterwards.
  """

  use ExUnit.Case, async: false

  alias Glific.Docs.{Indexer, Sync}

  @directory Path.join([File.cwd!(), "priv", "docs_kb"])

  setup do
    originals =
      Map.new(Indexer.documents(), fn document ->
        path = Path.join(@directory, "#{document}.md")
        {path, File.read!(path)}
      end)

    on_exit(fn ->
      Enum.each(originals, fn {path, body} -> File.write!(path, body) end)
      Application.delete_env(:glific, :docs_sync_request_options)
    end)

    %{originals: originals}
  end

  defp serve(fun), do: Application.put_env(:glific, :docs_sync_request_options, plug: fun)

  describe "url" do
    test "it names the repository the documents are written in" do
      assert Sync.url("glific_platform_guide") =~ "glific/dify"
      assert Sync.url("glific_platform_guide") =~ "glific_platform_guide.md"
    end
  end

  describe "a successful sync" do
    test "an unchanged document is reported as such and left alone", %{originals: originals} do
      serve(fn conn ->
        document = conn.request_path |> Path.basename(".md")
        path = Path.join(@directory, "#{document}.md")
        Plug.Conn.send_resp(conn, 200, Map.fetch!(originals, path))
      end)

      assert {:ok, %{changed: [], unchanged: unchanged}} = Sync.run()
      assert length(unchanged) == length(Indexer.documents())
    end

    test "a changed document is written and reported" do
      serve(fn conn -> Plug.Conn.send_resp(conn, 200, "# Replaced\n\nnew text\n") end)

      assert {:ok, %{changed: changed}} = Sync.run()
      assert length(changed) == length(Indexer.documents())
      assert File.read!(Path.join(@directory, "#{hd(changed)}.md")) =~ "Replaced"
    end
  end

  describe "a failed sync" do
    test "nothing is written when one document cannot be fetched", %{originals: originals} do
      # Otherwise the corpus ends up half from one revision and half from another.
      serve(fn conn ->
        if conn.request_path =~ List.last(Indexer.documents()),
          do: Plug.Conn.send_resp(conn, 500, "boom"),
          else: Plug.Conn.send_resp(conn, 200, "# Replaced\n\nnew text\n")
      end)

      assert {:error, message} = Sync.run()
      assert message =~ List.last(Indexer.documents())

      for {path, body} <- originals do
        assert File.read!(path) == body, "#{path} was modified despite the failure"
      end
    end
  end
end
