defmodule Glific.Scripts.GoldenQATest do
  use Glific.DataCase

  alias Ecto.Adapters.SQL.Sandbox
  alias FunWithFlags.Store.Cache
  alias Glific.FakeProvider
  alias Glific.Scripts.GoldenQA

  @input """
  id,question,expected_answer,expected_behaviour,topic,priority,needs_seed_data,seed_ids,human_rating,answer_status,source_thread
  A01,"How do I link a Google Sheet to a flow, and what is the ""Key"" column for?",Use the Link Google Sheets node.,A docs,google sheets,Priority 3,no,,5.00,verified,111
  F01,thanks!,RUBRIC: must not search.,F non-question,negative control,,no,,,rubric,synthetic
  """

  setup do
    original = Application.get_env(:glific, Glific.AI, [])
    Application.put_env(:glific, Glific.AI, Keyword.merge(original, FakeProvider.start()))
    FunWithFlags.enable(:glific_ai_enabled, for_actor: %{organization_id: 1})

    on_exit(fn ->
      Sandbox.checkout(Glific.Repo)
      FunWithFlags.disable(:glific_ai_enabled, for_actor: %{organization_id: 1})
      Cache.flush()
    end)

    on_exit(fn ->
      FakeProvider.stop()
      Application.put_env(:glific, Glific.AI, original)
    end)

    dir = System.tmp_dir!() |> Path.join("golden_qa_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    input = Path.join(dir, "golden.csv")
    File.write!(input, @input)
    on_exit(fn -> File.rm_rf!(dir) end)

    %{input: input, out: Path.join(dir, "golden-answers.csv")}
  end

  describe "running a golden set" do
    test "writes one answered row per question, carrying the labels through", %{
      input: input,
      out: out
    } do
      FakeProvider.always(FakeProvider.answer("knowledge"))

      assert :ok = GoldenQA.run(input, org_id: 1, delay_ms: 0)
      assert File.exists?(out)

      summary = GoldenQA.summarise(out)
      assert summary.answered == 2

      [header | _rows] = out |> File.read!() |> String.split("\n", trim: true)
      assert header =~ "expected_behaviour"
      assert header =~ "routed_skill"
      assert header =~ "checks"
      assert header =~ "seed_ids"
    end

    test "a question whose commas and quotes survive the round trip", %{input: input, out: out} do
      FakeProvider.always(FakeProvider.answer("knowledge"))

      GoldenQA.run(input, org_id: 1, delay_ms: 0)

      assert File.read!(out) =~ ~s(what is the ""Key"" column for?)
    end

    test "`only` keeps just the ids asked for", %{input: input, out: out} do
      FakeProvider.always(FakeProvider.answer("knowledge"))

      GoldenQA.run(input, org_id: 1, delay_ms: 0, only: "F")

      assert GoldenQA.summarise(out).answered == 1
      assert File.read!(out) =~ "F01"
      refute File.read!(out) =~ "A01"
    end

    test "a second run resumes rather than asking the provider again", %{input: input, out: out} do
      FakeProvider.always(FakeProvider.answer("knowledge"))
      GoldenQA.run(input, org_id: 1, delay_ms: 0)
      asked = length(FakeProvider.seen())

      GoldenQA.run(input, org_id: 1, delay_ms: 0)

      assert length(FakeProvider.seen()) == asked, "resuming should not re-ask the provider"
      assert GoldenQA.summarise(out).answered == 2
    end

    test "the flag being off stops the run instead of recording failures", %{input: input} do
      FunWithFlags.disable(:glific_ai_enabled, for_actor: %{organization_id: 1})
      Glific.Partners.fill_cache(Glific.Partners.organization(1))

      assert {:error, message} = GoldenQA.run(input, org_id: 1, delay_ms: 0)
      assert message =~ "glific_ai_enabled"
    end
  end
end
