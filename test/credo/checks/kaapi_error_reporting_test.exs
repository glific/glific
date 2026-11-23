Code.require_file("../../../.credo/checks/kaapi_error_reporting.ex", __DIR__)

defmodule GlificCredo.Checks.KaapiErrorReportingTest do
  use ExUnit.Case, async: true

  alias GlificCredo.Checks.KaapiErrorReporting

  setup_all do
    {:ok, _} = Application.ensure_all_started(:credo)
    :ok
  end

  defp issues(functions, opts \\ []) do
    module = Keyword.get(opts, :module, "Glific.Sample")
    filename = Keyword.get(opts, :filename, "lib/glific/sample.ex")

    """
    defmodule #{module} do
      #{functions}
    end
    """
    |> Credo.SourceFile.parse(filename)
    |> KaapiErrorReporting.run([])
  end

  test "flags a report of the result of a Kaapi call in the same function" do
    assert [_] =
             issues("""
             def create(config, organization_id) do
               case Kaapi.create_assistant_config(config, organization_id) do
                 {:ok, result} -> {:ok, result}
                 {:error, reason} ->
                   Glific.log_exception(%Error{message: "failed", reason: reason})
                   {:error, reason}
               end
             end
             """)
  end

  test "flags every reporter, through the alias or the full module name" do
    assert [_] = issues("def run(id), do: (Kaapi.delete_config(id, 1); Glific.log_error(\"x\"))")

    assert [_] =
             issues(
               "def run(id), do: (Glific.ThirdParty.Kaapi.delete_config(id, 1); Appsignal.send_error(:error, \"x\", []))"
             )
  end

  test "flags a report in a function that reaches Kaapi through a local function" do
    assert [_] =
             issues("""
             def create(params) do
               with {:ok, job} <- create_collection(params) do
                 {:ok, job}
               else
                 {:error, error} -> Glific.log_exception(%Error{message: "failed"})
               end
             end

             defp create_collection(params), do: Kaapi.create_collection(params, 1)
             """)
  end

  test "judges each clause on its own" do
    assert [] =
             issues("""
             def callback(%{"id" => id}), do: Kaapi.get_evaluation_scores(id, 1)
             def callback(params), do: Glific.log_exception(%Error{message: "bad payload"})
             """)
  end

  test "does not flag reports in functions that never reach Kaapi" do
    assert [] =
             issues("""
             def run(params) do
               Glific.log_exception(%Error{message: "failed", reason: params})
             end

             def other(id), do: Kaapi.delete_config(id, 1)
             """)
  end

  test "does not flag Logger calls or Kaapi.Error structs" do
    assert [] =
             issues("""
             def run(id) do
               with {:error, reason} <- Kaapi.delete_config(id, 1) do
                 Logger.error("failed")
                 %Kaapi.Error{message: "failed", reason: reason}
               end
             end
             """)
  end

  test "exempts the Kaapi client modules and test files" do
    body = "def run(id), do: (Kaapi.delete_config(id, 1); Glific.log_error(\"x\"))"

    assert [] = issues(body, module: "Glific.ThirdParty.Kaapi")
    assert [] = issues(body, module: "Glific.ThirdParty.Kaapi.ApiClient")
    assert [] = issues(body, filename: "test/glific/sample_test.exs")
  end
end
