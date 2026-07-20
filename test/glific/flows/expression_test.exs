defmodule Glific.Flows.ExpressionTest do
  use ExUnit.Case, async: true

  alias Glific.Flows.Expression

  doctest Glific.Flows.Expression

  # Every attack payload we expect to be rejected. Covers the denylist's known
  # gaps (alias/bare-atom/computed-module) plus the classic Elixir sinks.
  @attacks [
    ~s|<%= System.cmd("id", []) %>|,
    ~s|<%= elem(System.cmd("id", []), 0) %>|,
    ~s|<%= System.get_env("HOME") %>|,
    ~s|<%= File.read!("/etc/hostname") %>|,
    ~s|<%= IO.inspect("x") %>|,
    ~s|<%= Code.eval_string("1") %>|,
    ~s|<%= apply(System, :cmd, ["id", []]) %>|,
    ~s|<%= apply(:os, :cmd, [~c"id"]) %>|,
    ~s|<%= :os.cmd(~c"id") %>|,
    ~s|<%= :erlang.halt() %>|,
    ~s|<%= spawn(fn -> :ok end) %>|,
    ~s|<%= Process.list() %>|,
    "<%= alias System, as: T\nT.cmd(\"id\", []) %>",
    ~s|<%= :"Elixir.System".cmd("id", []) %>|,
    ~s|<%= Module.concat(["Sys", "tem"]).cmd("id", []) %>|,
    ~s|<%= (&System.cmd/2).("id", []) %>|,
    ~s|<%= (fn -> System.cmd("id", []) end).() %>|
  ]

  # The 9 real expressions found in the repo (post @-substitution they are all
  # arithmetic / rem / field access / one date call).
  @real [
    {"<%= 4 + 4 %>", %{}, "8"},
    {"<%= 5 * 60 %>", %{}, "300"},
    {"<%= rem(5, 2) %>", %{}, "1"},
    {"<%= rem(13 * 2 + 1, 6) %>", %{}, "3"},
    {"<%= @var + 1 %>", %{"var" => 4}, "5"}
  ]

  # Prose that flows through execute_eex today and must pass untouched.
  @prose [
    "Please apply for the scholarship before Friday",
    "You will receive a confirmation shortly",
    "Thanks for reaching out to our support agent",
    "Import your contacts from the dashboard"
  ]

  describe "eval/2 — safe expressions" do
    test "evaluates every real repo expression" do
      for {template, bindings, expected} <- @real do
        assert {:ok, ^expected} = Expression.eval(template, bindings), "for #{template}"
      end
    end

    test "evaluates string helpers and concatenation" do
      assert {:ok, "HELLO"} = Expression.eval(~s|<%= String.upcase("hello") %>|)
      assert {:ok, "ab"} = Expression.eval(~s|<%= "a" <> "b" %>|)
    end

    test "resolves @var field access from bindings" do
      assert {:ok, "Ada"} =
               Expression.eval("<%= @contact.name %>", %{"contact" => %{"name" => "Ada"}})
    end

    test "renders a date helper" do
      assert {:ok, iso} = Expression.eval("<%= Timex.today() %>")
      assert iso == Date.to_string(Date.utc_today())
    end

    test "substitutes a tag inside surrounding text" do
      assert {:ok, "You earned 5 points"} = Expression.eval("You earned <%= 2 + 3 %> points")
    end
  end

  describe "eval/2 — prose is never parsed" do
    test "returns non-expression prose unchanged" do
      for text <- @prose do
        assert {:ok, ^text} = Expression.eval(text), "for #{text}"
      end
    end
  end

  describe "eval/2 — fail-closed security boundary" do
    test "rejects every attack payload" do
      for payload <- @attacks do
        assert {:error, _} = Expression.eval(payload), "expected #{inspect(payload)} to reject"
      end
    end

    test "no filesystem side effects from attack payloads" do
      marker = "/tmp/glific_expr_poc_#{System.unique_integer([:positive])}"

      for payload <- [
            ~s|<%= File.write!("#{marker}", "x") %>|,
            ~s|<%= System.cmd("touch", ["#{marker}"]) %>|,
            ~s|<%= :os.cmd(~c"touch #{marker}") %>|
          ] do
        assert {:error, _} = Expression.eval(payload)
      end

      refute File.exists?(marker)
    end

    test "no module is reachable except the @mfa table (generative)" do
      hostile_modules = ~w(System File IO Code Process Node Kernel Application Port)
      hostile_funs = ~w(cmd exec eval read write halt to_atom system get_env)

      for m <- hostile_modules, f <- hostile_funs do
        payload = "<%= #{m}.#{f}(1) %>"
        assert {:error, _} = Expression.eval(payload), "expected #{payload} to reject"
      end
    end
  end

  describe "eval/2 — atom-table safety" do
    test "a novel hostile identifier is never interned as an atom" do
      unique = "zqxhostile#{System.unique_integer([:positive])}"

      assert {:error, _} = Expression.eval("<%= @#{unique}.field #{unique} %>", %{})

      # If the parser had interned it, this would succeed instead of raising.
      assert_raise ArgumentError, fn -> String.to_existing_atom(unique) end
    end

    test "many disjoint hostile identifiers are never interned" do
      ids = for i <- 1..200, do: "zqxbulk#{i}_#{System.unique_integer([:positive])}"

      for id <- ids do
        assert {:error, _} = Expression.eval("<%= @#{id}.f %>", %{})
      end

      # Deterministic + concurrency-safe: assert each specific hostile identifier
      # was never interned (checking the global atom_count is flaky under async).
      for id <- ids do
        assert_raise ArgumentError, fn -> String.to_existing_atom(id) end
      end
    end
  end

  describe "eval/2 — resource & error limits" do
    test "rejects an over-complex expression (node cap)" do
      big = "<%= " <> Enum.map_join(1..200, " + ", fn _ -> "1" end) <> " %>"
      assert {:error, "expression too complex"} = Expression.eval(big)
    end

    test "rejects oversized output" do
      big = String.duplicate("a", 11_000)
      assert {:error, "expression output too large"} = Expression.eval(~s|<%= "#{big}" %>|)
    end

    test "rejects division and remainder by zero" do
      assert {:error, _} = Expression.eval("<%= 5 / 0 %>")
      assert {:error, _} = Expression.eval("<%= rem(5, 0) %>")
      assert {:error, _} = Expression.eval("<%= div(5, 0) %>")
    end

    test "rejects invalid syntax; an unbound variable is nil (empty)" do
      assert {:error, _} = Expression.eval("<%= 4 + %>")
      assert {:ok, ""} = Expression.eval("<%= @missing %>", %{})
    end

    # Note: timeout / heap-kill in isolated/1 are backstops. They are effectively
    # unreachable via expressions because the vocabulary has no loops, recursion
    # or comprehensions and the AST is capped at @max_nodes, so evaluation is
    # O(nodes)-bounded and total. This test just confirms a legal, moderately
    # sized expression completes through the isolation boundary.
    test "a legal near-limit expression still evaluates" do
      expr = "<%= " <> Enum.map_join(1..40, " + ", fn _ -> "2" end) <> " %>"
      assert {:ok, "80"} = Expression.eval(expr)
    end
  end

  describe "compile/1 + validate/1 (publish time)" do
    test "validate accepts safe templates" do
      assert :ok = Expression.validate("<%= 4 + 4 %>")
      assert :ok = Expression.validate("Hi <%= @contact.fields.enrollment_status %>")
    end

    test "validate rejects every attack payload" do
      for payload <- @attacks do
        assert {:error, _} = Expression.validate(payload),
               "expected #{inspect(payload)} to reject"
      end
    end

    test "validate/1 and eval/2 agree on the deny corpus (drift guard)" do
      for payload <- @attacks do
        assert {:error, _} = Expression.validate(payload)
        assert {:error, _} = Expression.eval(payload)
      end
    end

    test "compile accepts novel custom-field identifiers (atoms_only: false)" do
      novel = "enrollment_status_#{System.unique_integer([:positive])}"
      assert {:ok, _} = Expression.compile("<%= @contact.fields.#{novel} %>")
    end
  end

  describe "render/2 — bindings never become code (Phase 2)" do
    test "a hostile binding value is treated as data, not re-evaluated" do
      {:ok, compiled} = Expression.compile("Hi <%= @contact.name %>")

      {:ok, out} = Expression.render(compiled, %{"contact" => %{"name" => "<%= 6*7 %>"}})

      assert out == "Hi <%= 6*7 %>"
      refute out =~ "42"
    end

    test "renders arithmetic from a compiled template" do
      {:ok, compiled} = Expression.compile("<%= 6 * 7 %>")
      assert {:ok, "42"} = Expression.render(compiled, %{})
    end
  end

  describe "eval/2 — control-flow forms" do
    test "if / else" do
      assert {:ok, "yes"} = Expression.eval("<%= if 3 > 2, do: \"yes\", else: \"no\" %>")
      assert {:ok, "no"} = Expression.eval("<%= if 1 > 2, do: \"yes\", else: \"no\" %>")
    end

    test "cond" do
      template = "<%= cond do @n > 3 -> \"big\"; true -> \"small\" end %>"
      assert {:ok, "big"} = Expression.eval(template, %{"n" => 5})
      assert {:ok, "small"} = Expression.eval(template, %{"n" => 1})
    end

    test "pipe chain" do
      assert {:ok, "HI"} =
               Expression.eval("<%= \"  hi  \" |> String.trim() |> String.upcase() %>")
    end

    test "short-circuit && / ||" do
      assert {:ok, "true"} = Expression.eval("<%= @n > 0 && @n <= 10 %>", %{"n" => 5})
      assert {:ok, "default"} = Expression.eval("<%= @missing || \"default\" %>", %{})
    end

    test "in operator and string interpolation" do
      assert {:ok, "true"} = Expression.eval("<%= @n in [1, 2, 5] %>", %{"n" => 5})
      assert {:ok, "count: 5"} = Expression.eval(~S(<%= "count: #{@n}" %>), %{"n" => 5})
    end

    test "multi-statement block with local assignment" do
      assert {:ok, "9"} = Expression.eval("<%= x = 3\nx * x %>", %{})
    end

    test "expanded function allowlist" do
      assert {:ok, "a-b-c"} = Expression.eval("<%= String.replace(\"a b c\", \" \", \"-\") %>")
      assert {:ok, "5"} = Expression.eval("<%= String.to_integer(\"5\") %>")
    end

    test "ranges and Enum.sort_by with a capture" do
      assert {:ok, "3"} = Expression.eval("<%= Enum.count(1..3) %>")

      {:ok, compiled} = Expression.compile("<%= Enum.at(Enum.sort_by(@l, &(-&1)), 0) %>")
      assert {:ok, "5"} = Expression.render(compiled, %{"l" => [3, 5, 1]})
    end

    test "keyword arguments (Timex.shift) validate the value" do
      assert :ok = Expression.validate("<%= Timex.shift(@d, days: 1) %>")
      assert :ok = Expression.validate("<%= Timex.shift(@d, days: 1, hours: 2) %>")
      # a disallowed call in a keyword value is still rejected
      assert {:error, _} =
               Expression.validate("<%= Timex.shift(@d, days: System.cmd(\"id\", [])) %>")
    end

    test "literal regex sigil; interpolated patterns are rejected" do
      assert {:ok, "true"} = Expression.eval(~S|<%= Regex.match?(~r/ab/, "xabc") %>|)
      assert {:ok, "a-b"} = Expression.eval(~S|<%= Regex.replace(~r/\s/, "a b", "-") %>|)
      # an interpolated pattern (multi-part <<>>) is not a compile-time regex
      assert {:error, _} = Expression.validate(~S|<%= Regex.match?(~r/#{@x}/, "y") %>|)
    end

    test "calendar sigils, map literals, hd/is_map" do
      assert {:ok, "12:30:00"} = Expression.eval("<%= ~T[12:30:00] %>")
      assert {:ok, "2"} = Expression.eval(~S|<%= Map.get(%{"a" => 1, "b" => 2}, "b") %>|)
      assert {:ok, "3"} = Expression.eval("<%= hd([3, 4]) %>")
      # a disallowed call inside a map value is still rejected
      assert {:error, _} = Expression.validate(~S|<%= %{a: System.cmd("id", [])} %>|)
    end

    test "~s string sigil renders (plain and interpolated); disallowed calls inside are rejected" do
      assert {:ok, "hello"} = Expression.eval("<%= ~s(hello) %>")
      # angle-bracket delimiter, same AST
      assert {:ok, "0"} = Expression.eval("<%= ~s<0> %>")
      # interpolation is evaluated through the allowlist
      assert {:ok, "n=8"} = Expression.eval("<%= ~s(n=#{4 + 4}) %>")
      # a disallowed call spliced via interpolation is still rejected
      assert {:error, _} = Expression.validate(~S|<%= ~s(#{System.cmd("id", [])}) %>|)
    end

    test "bracket access foo[key] on maps (incl. Jason.decode! result); non-maps rejected" do
      assert {:ok, "2"} = Expression.eval(~S|<%= %{"a" => 1, "b" => 2}["b"] %>|)
      # the real corpus shape: decode a JSON string, then index it
      assert {:ok, "hi"} = Expression.eval(~S|<%= Jason.decode!(~s({"m":"hi"}))["m"] %>|)

      # a missing key is nil (empty output), nil container is nil
      assert {:ok, ""} = Expression.eval(~S|<%= %{"a" => 1}["missing"] %>|)
      # bracket access on a non-map degrades to an error, never a crash
      assert {:error, _} = Expression.eval(~S|<%= [1, 2, 3]["x"] %>|)
      # a disallowed call inside the key/container is still rejected
      assert {:error, _} = Expression.validate(~S|<%= %{"a" => 1}[System.cmd("id", [])] %>|)
    end

    test "newly allowlisted pure functions (Decimal, Enum, List, Timex)" do
      assert {:ok, "6"} = Expression.eval("<%= Decimal.mult(2, 3) %>")
      assert {:ok, "3"} = Expression.eval("<%= Decimal.div(9, 3) %>")
      assert {:ok, "6"} = Expression.eval("<%= Enum.sum([1, 2, 3]) %>")
      assert {:ok, "a, b"} = Expression.eval(~S|<%= Enum.map_join(["a", "b"], ", ", &(&1)) %>|)
      assert {:ok, "1"} = Expression.eval("<%= Enum.count(List.wrap(1)) %>")
    end

    test "anonymous functions (fn and & capture) with Enum" do
      results = %{"results" => %{"list" => [1, 2, 3, 4, 5]}}

      {:ok, c1} = Expression.compile("<%= Enum.find(@results.list, fn x -> x > 3 end) %>")
      assert {:ok, "4"} = Expression.render(c1, results)

      {:ok, c2} = Expression.compile("<%= Enum.count(Enum.reject(@results.list, &(&1 > 3))) %>")
      assert {:ok, "3"} = Expression.render(c2, results)

      assert {:ok, "10"} = Expression.eval("<%= 5 |> then(fn v -> v * 2 end) %>")
    end

    test "a closure body cannot escape the allowlist" do
      for payload <- [
            "<%= Enum.find(@l, fn x -> System.cmd(x, []) end) %>",
            "<%= Enum.map(@l, &(File.read!(&1))) %>"
          ] do
        assert {:error, _} = Expression.validate(payload), "expected #{payload} to reject"
      end
    end

    test "deeply nested if-in group routing (real flow: Activity Capgemini)" do
      groups =
        ~w(TAP_1_Art_L3_1 TAP_1_Art_L2_1 TAP_2_Art_L3_1 TAP_2_Art_L3_2 TAP_3_Art_L2_1
           TAP_3_Art_L2_2 TAP_3_Art_L2_3 TAP_4_Art_L2_1 TAP_4_Art_L2_2 TAP_4_Art_L2_3
           TAP_5_Art_L2_1 TAP_5_Art_L2_2)

      inner =
        groups
        |> Enum.reverse()
        |> Enum.reduce("2", fn group, acc ->
          ~s(if "#{group}" in @contact.in_groups, do: 1, else: #{acc})
        end)

      operand = "<%= " <> inner <> " %>"

      assert {:ok, compiled} = Expression.compile(operand)

      assert {:ok, "1"} =
               Expression.render(compiled, %{"contact" => %{"in_groups" => ["TAP_3_Art_L2_2"]}})

      assert {:ok, "2"} =
               Expression.render(compiled, %{"contact" => %{"in_groups" => ["not_a_group"]}})
    end

    test "allowlisted send_template builds a payload (pure); multi-segment modules" do
      assert {:ok, json} = Expression.eval("<%= Glific.send_template(\"uuid\", [\"a\"]) %>")
      assert json =~ "uuid"

      # per-NGO client module (multi-segment alias) resolves too
      assert :ok =
               Expression.validate("<%= Glific.Clients.PehlayAkshar.send_template(\"u\", []) %>")

      # per-NGO template/2 payload builders (also pure)
      assert :ok =
               Expression.validate("<%= Glific.Clients.ArogyaWorld.template(\"u\", []) %>")

      assert :ok = Expression.validate("<%= Glific.Clients.Tap.template(\"code\", \"\") %>")

      # but unknown multi-segment modules/functions are still rejected
      assert {:error, _} = Expression.validate("<%= Glific.Clients.Evil.cmd(\"id\") %>")
      assert {:error, _} = Expression.validate("<%= Glific.Repo.all() %>")
    end

    test "safe unit atoms are allowed, module-name atoms are not" do
      # time-unit atom passed to an allowlisted function
      assert {:ok, "5"} =
               Expression.eval(
                 "<%= Date.diff(Date.from_iso8601!(\"2026-01-06\"), Date.from_iso8601!(\"2026-01-01\")) %>"
               )

      assert :ok = Expression.validate("<%= DateTime.diff(@a, @b, :second) %>")
      assert :ok = Expression.validate("<%= Time.diff(@a, @b, :minute) %>")

      # module-name atoms stay rejected (defence in depth), and a bare-atom
      # module call still has no clause and rejects regardless
      assert {:error, _} = Expression.validate("<%= :os %>")
      assert {:error, _} = Expression.validate("<%= :os.system_time(:second) %>")
      assert {:error, _} = Expression.validate("<%= :crypto.hash(:sha, \"x\") %>")
    end

    test "control-flow forms do not become an escape hatch" do
      for payload <- [
            "<%= if true, do: System.cmd(\"id\", []), else: 0 %>",
            "<%= \"x\" |> System.cmd([]) %>",
            "<%= true && File.read!(\"/etc/hostname\") %>",
            "<%= cond do true -> :os.cmd(~c\"id\") end %>"
          ] do
        assert {:error, _} = Expression.eval(payload), "expected #{payload} to reject"
        assert {:error, _} = Expression.validate(payload)
      end
    end
  end
end
