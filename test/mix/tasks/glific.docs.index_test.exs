defmodule Mix.Tasks.Glific.Docs.IndexTest do
  @moduledoc """
  The task that rebuilds the embedding artifact.

  The embedding provider and the documentation repository are both stubbed, so
  nothing here reaches the network or spends anything.
  """

  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  alias Glific.Docs
  alias Mix.Tasks.Glific.Docs.Index, as: Task

  setup %{tmp_dir: tmp_dir} do
    # Never the committed artifact: a test that aborts mid-run would leave a
    # corrupt binary in the tree, and every search would score zero.
    Mix.shell(Mix.Shell.Process)
    Application.put_env(:glific, Glific.Docs, artifact_path: Path.join(tmp_dir, "embeddings.etf"))

    on_exit(fn ->
      Application.put_env(:glific, Glific.Docs,
        embedding_model: "openai:text-embedding-3-small",
        embedding_dimensions: 256
      )

      Application.delete_env(:glific, :docs_embedding_request_options)
      Mix.shell(Mix.Shell.IO)
      Docs.warm()
    end)

    :ok
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
      assert printed =~ Docs.artifact_path()
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
end
