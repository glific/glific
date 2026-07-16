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

  describe "eval/2 — safe expressions (AC-1)" do
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

  describe "eval/2 — prose is never parsed (AC-1)" do
    test "returns non-expression prose unchanged" do
      for text <- @prose do
        assert {:ok, ^text} = Expression.eval(text), "for #{text}"
      end
    end
  end

  describe "eval/2 — fail-closed security boundary (AC-2)" do
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

  describe "eval/2 — atom-table safety (AC-3)" do
    test "a novel hostile identifier is never interned as an atom" do
      unique = "zqxhostile#{System.unique_integer([:positive])}"

      assert {:error, _} = Expression.eval("<%= @#{unique}.field #{unique} %>", %{})

      # If the parser had interned it, this would succeed instead of raising.
      assert_raise ArgumentError, fn -> String.to_existing_atom(unique) end
    end

    test "many disjoint hostile identifiers do not grow the atom table" do
      before_count = :erlang.system_info(:atom_count)

      for i <- 1..200 do
        assert {:error, _} =
                 Expression.eval(
                   "<%= @zqxbulk#{i}_#{System.unique_integer([:positive])}.f %>",
                   %{}
                 )
      end

      # atoms are permanent; the interpreter must intern none of the above.
      assert :erlang.system_info(:atom_count) == before_count
    end
  end

  describe "eval/2 — resource & error limits (AC-4)" do
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

    test "validate rejects every attack payload (AC-5)" do
      for payload <- @attacks do
        assert {:error, _} = Expression.validate(payload),
               "expected #{inspect(payload)} to reject"
      end
    end

    test "validate/1 and eval/2 agree on the deny corpus (AC-5 drift guard)" do
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

  describe "render/2 — bindings never become code (AC-7, Phase 2)" do
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
