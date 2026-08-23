defmodule Glific.AI.Evals.DeterminismTest do
  @moduledoc """
  The prompt-cache determinism guard, for every registered skill (`Glific.AI.Skill.Registry.all/0`).

  Provider prompt caching keys off a byte-identical prefix between calls (see
  `Glific.AI.Skill`'s own moduledoc). A `system_prompt/1` that embeds a timestamp, "today is …",
  the result of `Enum.shuffle/1`, or text built from map iteration order still *works* — the
  model still answers — it just silently pays full price on every call instead of a cached
  read, with no error and no functional symptom pointing at the cause. The same is true of a
  tool's `parameters/0`, which is serialised into every request alongside the prompt.

  This is a cost regression with no functional symptom, which is exactly the kind of bug that
  survives for months undetected. This test is the only cheap guard against it: render/serialise
  twice with the same input and assert byte equality. It makes no model call and needs no
  database, so it belongs in the cheap, deterministic `:eval` tier that runs in CI on every PR.

  Uses one fixed input map rather than depending on any particular skill's input shape, and
  skips (rather than fails) a skill whose `validate_input/1` rejects that fixed input — this
  test is about determinism of the *output*, not about exercising every skill's own input
  validation, which its own unit tests already cover.
  """

  use ExUnit.Case, async: true

  @moduletag :eval

  alias Glific.AI.Skill.Registry

  @fixed_input %{"message" => "determinism probe", "topic" => "determinism probe"}

  describe "system_prompt/1" do
    test "every skill renders a byte-identical prompt across two calls with the same input" do
      for skill <- Registry.all(), {:ok, validated} <- [skill.validate_input(@fixed_input)] do
        first = skill.system_prompt(validated)
        second = skill.system_prompt(validated)

        assert first == second,
               "#{inspect(skill)}.system_prompt/1 is not byte-identical across two calls " <>
                 "with the same input — this defeats provider prompt caching"
      end
    end
  end

  describe "tools/0 parameters" do
    test "every skill's tools serialise their parameters/0 byte-identically across two calls" do
      for skill <- Registry.all(), tool <- skill.tools() do
        first = tool.parameters() |> ReqLLM.Schema.to_json() |> Jason.encode!()
        second = tool.parameters() |> ReqLLM.Schema.to_json() |> Jason.encode!()

        assert first == second,
               "#{inspect(tool)}.parameters/0 does not serialise byte-identically across " <>
                 "two calls — this defeats provider prompt caching for #{inspect(skill)}"
      end
    end
  end
end
