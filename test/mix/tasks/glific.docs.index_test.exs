defmodule Mix.Tasks.Glific.Docs.IndexTest do
  @moduledoc """
  The task that rebuilds the embedding artifact.

  The embedding provider and the documentation repository are both stubbed, so
  nothing here reaches the network or spends anything.
  """

  use ExUnit.Case, async: false

  alias Glific.Docs.{Index, Indexer}
  alias Mix.Tasks.Glific.Docs.Index, as: Task

  @directory Path.join([File.cwd!(), "priv", "docs_kb"])

  setup do
    Mix.shell(Mix.Shell.Process)

    artifacts = [Index.artifact_path(), Path.join(@directory, "embeddings.etf")]
    original = artifacts |> Enum.find(&File.exists?/1) |> File.read!()

    documents =
      Map.new(Indexer.documents(), fn document ->
        path = Path.join(@directory, "#{document}.md")
        {path, File.read!(path)}
      end)

    on_exit(fn ->
      Enum.each(artifacts, &File.write!(&1, original))
      Enum.each(documents, fn {path, body} -> File.write!(path, body) end)
      Application.delete_env(:glific, :docs_embedding_request_options)
      Application.delete_env(:glific, :docs_sync_request_options)
      Mix.shell(Mix.Shell.IO)
      Index.warm()
    end)

    %{documents: documents}
  end

  defp stub_embeddings(dimensions) do
    Application.put_env(:glific, :docs_embedding_request_options,
      req_http_options: [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          inputs = body |> Jason.decode!() |> Map.fetch!("input") |> List.wrap()

          data =
            Enum.with_index(inputs, fn _input, index ->
              %{"embedding" => List.duplicate(0.1, dimensions), "index" => index}
            end)

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(%{"data" => data, "model" => "stub"}))
        end
      ]
    )
  end

  defp output do
    receive do
      {:mix_shell, :info, [message]} -> message <> output()
    after
      0 -> ""
    end
  end

  describe "a plain run" do
    test "it reports what it chunked, embedded and wrote" do
      stub_embeddings(8)

      assert :ok = Task.run(["--force", "--dimensions", "8"])

      printed = output()
      assert printed =~ "Chunking"
      assert printed =~ "sections"
      assert printed =~ "Indexed"
      assert printed =~ "8 dimensions"
      assert printed =~ "Wrote"
      assert printed =~ Index.artifact_path()
    end

    test "a second run reports everything reused" do
      stub_embeddings(8)
      Task.run(["--force", "--dimensions", "8"])
      _first = output()

      assert :ok = Task.run(["--dimensions", "8"])
      assert output() =~ "embedded  0"
    end

    test "the model can be chosen on the command line" do
      stub_embeddings(8)

      assert :ok =
               Task.run([
                 "--force",
                 "--dimensions",
                 "8",
                 "--model",
                 "openai:text-embedding-3-large"
               ])

      assert output() =~ "text-embedding-3-large"
    end
  end

  describe "--sync" do
    test "it pulls the documents before indexing and says what changed" do
      stub_embeddings(8)

      Application.put_env(:glific, :docs_sync_request_options,
        plug: fn conn -> Plug.Conn.send_resp(conn, 200, "# Replaced\n\n" <> body()) end
      )

      assert :ok = Task.run(["--sync", "--force", "--dimensions", "8"])

      printed = output()
      assert printed =~ "Synced from glific/dify, updated:"
      assert printed =~ "Indexed"
    end

    test "unchanged documents are reported as unchanged", %{documents: documents} do
      stub_embeddings(8)

      Application.put_env(:glific, :docs_sync_request_options,
        plug: fn conn ->
          document = Path.basename(conn.request_path, ".md")

          Plug.Conn.send_resp(
            conn,
            200,
            Map.fetch!(documents, Path.join(@directory, "#{document}.md"))
          )
        end
      )

      assert :ok = Task.run(["--sync", "--force", "--dimensions", "8"])
      assert output() =~ "none changed"
    end

    test "a failed sync stops the run rather than indexing a half-updated corpus" do
      Application.put_env(:glific, :docs_sync_request_options,
        plug: fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end
      )

      assert_raise Mix.Error, ~r/Sync failed/, fn ->
        Task.run(["--sync"])
      end
    end
  end

  describe "failures" do
    test "a provider error is raised rather than reported as success" do
      Application.put_env(:glific, :docs_embedding_request_options,
        req_http_options: [plug: fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end]
      )

      assert_raise Mix.Error, ~r/Indexing failed/, fn ->
        Task.run(["--force"])
      end
    end

    test "an unknown switch is rejected" do
      assert_raise OptionParser.ParseError, fn -> Task.run(["--nonsense"]) end
    end
  end

  defp body, do: String.duplicate("A replacement document long enough to chunk. ", 8)
end
