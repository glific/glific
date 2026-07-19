defmodule GlificTest do
  use Glific.DataCase

  describe "execute_eex/1 flow-expression guard" do
    @blocked_marker "Suspicious Code. Please change your code."

    test "evaluates a legitimate, safe expression" do
      assert Glific.execute_eex("<%= rem(5, 2) %>") == "1"
    end

    test "blocks OS command execution via System.cmd/2" do
      payload = ~s|<%= System.cmd("touch", ["/tmp/glific_poc_marker"]) %>|
      assert Glific.suspicious_code(payload)
      assert Glific.execute_eex(payload) =~ @blocked_marker
      refute File.exists?("/tmp/glific_poc_marker")
    end

    test "blocks command output exfiltration via System.cmd/2" do
      payload = ~s|<%= elem(System.cmd("id", []), 0) %>|
      assert Glific.execute_eex(payload) =~ @blocked_marker
    end

    test "blocks the omitted tokens" do
      for payload <- [
            ~s|<%= System.get_env("HOME") %>|,
            ~s|<%= :os.cmd(~c"id") %>|,
            ~s|<%= :erlang.halt() %>|,
            ~s|<%= apply(System, :cmd, ["id", []]) %>|,
            ~s|<%= apply(:os, :cmd, [~c"id"]) %>|,
            ~s|<%= spawn(fn -> :ok end) %>|,
            ~s|<%= Process.list() %>|,
            ~s|<%= File.read!("/etc/hostname") %>|,
            ~s|<%= IO.inspect("x") %>|,
            ~s|<%= Code.eval_string("1") %>|
          ] do
        assert Glific.suspicious_code(payload), "expected #{payload} to be flagged"
        assert Glific.execute_eex(payload) =~ @blocked_marker
      end
    end

    test "does not flag ordinary message text that merely contains the words" do
      # These flow through execute_eex/1 via set_run_result, contact fields and
      # templating; they must not be mistaken for code.
      for text <- [
            "Please apply for the scholarship before Friday",
            "You will receive a confirmation shortly",
            "Thanks for reaching out to our support agent",
            "Import your contacts from the dashboard"
          ] do
        refute Glific.suspicious_code(text), "expected #{text} to be allowed"
      end
    end
  end

  describe "execute_eex/1 with the :safe_expressions flag enabled" do
    @blocked_marker "Suspicious Code. Please change your code."

    setup do
      # Use a fresh org so the ETS-cached flag never collides with (or leaks into)
      # the shared org-1 tests; the DB write rolls back with the SQL sandbox.
      organization = Glific.Fixtures.organization_fixture()
      Glific.Repo.put_organization_id(organization.id)
      FunWithFlags.enable(:safe_expressions, for_actor: %{organization_id: organization.id})

      %{organization: organization}
    end

    test "renders a safe expression through the interpreter (never EEx)" do
      assert Glific.execute_eex("<%= rem(5, 2) %>") == "1"
      assert Glific.execute_eex("You earned <%= 4 + 4 %> points") == "You earned 8 points"
    end

    test "the denylist still blocks dangerous code before the interpreter runs" do
      payload = ~s|<%= System.cmd("touch", ["/tmp/glific_poc_marker"]) %>|
      assert Glific.execute_eex(payload) =~ @blocked_marker
      refute File.exists?("/tmp/glific_poc_marker")
    end

    test "an expression the interpreter cannot handle degrades to Invalid Code, not EEx" do
      # `with` is not supported by the interpreter; the enabled path must reject it
      # rather than silently falling back to EEx.
      assert Glific.execute_eex("<%= with x <- 1, do: x %>") == "Invalid Code"
    end
  end
end
