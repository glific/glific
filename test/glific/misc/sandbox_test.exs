defmodule Glific.SandboxTest do
  use ExUnit.Case

  alias Glific.{Sandbox, SandboxTest}

  doctest Sandbox

  def mobility(state, _args) do
    state
    |> Sandbox.set!("x", 3)
    |> Sandbox.set!("feeling", "poo")
    |> Sandbox.set!("hunger", 7)
    |> Sandbox.let_elixir_run!("move", &SandboxTest.move/2)
    |> Sandbox.let_elixir_eval!("feels", fn _state, [p | _] -> to_string(p) <> " feels" end)
  end

  def move(state, [d | _rest]) do
    x = state |> Sandbox.get!("x")
    result = x + d
    new_state = state |> Sandbox.set!("x", result)
    {result, new_state}
  end

  test "can set value" do
    output =
      Sandbox.init()
      |> Sandbox.set!("some_variable", "some_value")
      |> Sandbox.eval!("return some_variable")

    assert output == "some_value"
  end

  test "can set value at path" do
    output =
      Sandbox.init()
      |> Sandbox.set!("some_table", [])
      |> Sandbox.set!(["some_table", "some_variable"], "some_value")
      |> Sandbox.eval!("return some_table.some_variable")

    assert output == "some_value"
  end

  test "can set value at path with dot notation" do
    output =
      Sandbox.init()
      |> Sandbox.set!("some_table", [])
      |> Sandbox.set!("some_table.some_variable", "some_value")
      |> Sandbox.eval!("return some_table.some_variable")

    assert output == "some_value"
  end

  test "can set value at path with dot notation and fail with missing table" do
    assert catch_error(
             Sandbox.init()
             |> Sandbox.set!("some_table.some_variable", "some_value")
             |> Sandbox.eval!("return some_table.some_variable")
           )
  end

  test "can set value at path with dot notation and force missing table creation" do
    output =
      Sandbox.init()
      |> Sandbox.set!("some_table.some_variable", "some_value", true)
      |> Sandbox.eval!("return some_table.some_variable")

    assert output == "some_value"
  end

  test "can set value at path and not need forced table creation" do
    output =
      Sandbox.init()
      |> Sandbox.set!("some_table", [], true)
      |> Sandbox.set!(["some_table", "some_variable"], "some_value", true)
      |> Sandbox.eval!("return some_table.some_variable")

    assert output == "some_value"
  end

  test "can get value at path with get!" do
    output =
      Sandbox.init()
      |> Sandbox.set!("some_table", [])
      |> Sandbox.set!("some_table.some_variable", "some_value")
      |> Sandbox.get!(["some_table", "some_variable"])

    assert output == "some_value"
  end

  test "can call function at path" do
    output =
      Sandbox.init()
      |> Sandbox.play_file!("test/lua/animal.lua")
      |> Sandbox.eval_function!(["speak"], ["bunny"])

    assert output == "silence"
  end

  test "can call function at path as string" do
    output =
      Sandbox.init()
      |> Sandbox.play_file!("test/lua/animal.lua")
      |> Sandbox.eval_function!("speak", ["cow"], 0)

    assert output == "moo"
  end

  test "can call function returning an object" do
    output =
      Sandbox.init()
      |> Sandbox.play_file!("test/lua/animal.lua")
      |> Sandbox.eval_function!("voices", [], 0)

    assert output == [
             {"bunny", "silence"},
             {"cat", "meow"},
             {"cow", "moo"},
             {"dog", "woof"}
           ]
  end

  test "can call function at path with single arg wrapped as array" do
    output =
      Sandbox.init()
      |> Sandbox.play_file!("test/lua/animal.lua")
      |> Sandbox.eval_function!("speak", "dog", 100_000)

    assert output == "woof"
  end

  test "can handle chunks" do
    state = Sandbox.init()

    code =
      state
      |> Sandbox.chunk!("return 7")

    output = Sandbox.eval!(state, code)
    assert output == 7
  end

  test "can chunk against file defined functions" do
    state = Sandbox.init()

    code =
      state
      |> Sandbox.chunk!("return 7")

    output = Sandbox.eval!(state, code)
    assert output == 7
  end

  test "can expose Elixir function" do
    state = Sandbox.init()

    output =
      state
      |> Sandbox.let_elixir_eval!("puppy", fn _state, p -> to_string(p) <> " is cute" end)
      |> Sandbox.eval_function!("puppy", "dog", 10_000)

    assert output == "dog is cute"
  end

  test "can expose Elixir function that reaches reduction limit" do
    state = Sandbox.init()

    long_function = fn ->
      state
      |> Sandbox.let_elixir_eval!("puppy", fn _state, p ->
        Enum.map(1..10_000, fn _ -> to_string(p) <> " is cute" end)
        |> List.last()
      end)
      |> Sandbox.eval_function!("puppy", "dog", 2000)
    end

    assert_raise(RuntimeError, Sandbox.reduction_error(), long_function)
  end

  test "can play a Lua function that updates the Lua state" do
    state = Sandbox.init()

    output =
      state
      |> Sandbox.play_file!("test/lua/animal.lua")
      |> Sandbox.play_function!(["talk"], 4, 10_000)
      |> Sandbox.get!("counter")

    assert output == 4
  end

  test "can play a Lua function without arguments that updates the Lua state" do
    state = Sandbox.init()

    output =
      state
      |> Sandbox.play_file!("test/lua/animal.lua")
      |> Sandbox.play_function!("sleep")
      |> Sandbox.get!("sleeping")

    assert output == true
  end

  test "can run Lua to update the Lua state with no return value" do
    state = Sandbox.init()

    {:ok, {_result, new_state}} =
      state
      |> Sandbox.play_file!("test/lua/animal.lua")
      |> Sandbox.run("sleeping = true")

    output = new_state |> Sandbox.get!("sleeping")

    assert output == true
  end

  test "can run a Lua function that updates the Lua state" do
    state = Sandbox.init()

    {output, _new_state} =
      state
      |> Sandbox.play_file!("test/lua/animal.lua")
      |> Sandbox.run_function!("talk", 4, 10_000)

    assert output == 4
  end

  test "can chunk a Lua function and then use it" do
    state = Sandbox.init()
    code = "function growl(n)\nreturn n + 2\nend"
    chunk = Sandbox.chunk!(state, code)

    output =
      state
      |> Sandbox.play!(chunk)
      |> Sandbox.eval_function!("growl", 7)

    assert output == 9
  end

  test "can play functionality to state through Elixir" do
    state = Sandbox.init()

    output =
      state
      |> Sandbox.let_elixir_play!("inherit_mobility", &SandboxTest.mobility/2)
      |> Sandbox.eval_file!("test/lua/mobility.lua")

    assert output == "happy feels"
  end

  test "can play functionality to state through Elixir with ok-error tuple" do
    state = Sandbox.init()

    {:ok, output} =
      state
      |> Sandbox.let_elixir_play!("inherit_mobility", &SandboxTest.mobility/2)
      |> Sandbox.eval_file("test/lua/mobility.lua")

    assert output == "happy feels"
  end

  test "can play functionality to state through Elixir with ok-error tuple and hit reduction limit" do
    state = Sandbox.init()

    output =
      state
      |> Sandbox.let_elixir_play!("inherit_mobility", &SandboxTest.mobility/2)
      #      |> Sandbox.eval_function!("waste_cycles", [1_000])
      |> Sandbox.eval_file("test/lua/mobility.lua", 1000)

    assert {:error, {:reductions, _}} = output
  end

  test "can get value" do
    output =
      Sandbox.init()
      |> Sandbox.set!("some_variable", "some_value")
      |> Sandbox.get!("some_variable")

    assert output == "some_value"
  end

  test "can get value from unsafe init" do
    output =
      Sandbox.unsafe_init()
      |> Sandbox.set!("some_variable", "some_value")
      |> Sandbox.get!("some_variable")

    assert output == "some_value"
  end
end
