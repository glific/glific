defmodule Glific.AI.ActorTest do
  use Glific.DataCase

  alias Glific.AI.Actor
  alias Glific.Fixtures
  alias Glific.Partners
  alias Glific.Repo
  alias Glific.RepoReplica
  alias Glific.Users.User

  describe "put!/2" do
    test "acts as the requesting user, not the organisation root", %{organization_id: org_id} do
      requester = Fixtures.user_fixture(%{organization_id: org_id})

      acting = Actor.put!(org_id, requester.id)

      assert acting.id == requester.id
      assert Repo.get_organization_id() == org_id
      assert %User{id: id} = Repo.get_current_user()
      assert id == requester.id

      root_user = Partners.organization(org_id).root_user
      refute acting.id == root_user.id
    end

    test "sets the replica store too, not only the primary", %{organization_id: org_id} do
      requester = Fixtures.user_fixture(%{organization_id: org_id})

      Actor.put!(org_id, requester.id)

      assert %User{id: id} = RepoReplica.get_current_user()
      assert id == requester.id
    end

    test "refuses a user from another organisation", %{organization_id: org_id} do
      other_org = Fixtures.organization_fixture(%{shortcode: "otheractor"})
      outsider = Fixtures.user_fixture(%{organization_id: other_org.id})

      assert_raise Actor.Error, ~r/no user .* in organization/, fn ->
        Actor.put!(org_id, outsider.id)
      end
    end
  end

  describe "assert!/2 — the runtime detector for the root_user trap" do
    test "passes while the correct actor is set", %{organization_id: org_id} do
      requester = Fixtures.user_fixture(%{organization_id: org_id})
      Actor.put!(org_id, requester.id)

      assert :ok == Actor.assert!(org_id, requester.id)
    end

    test "fails loudly if put_process_state/1 replaced the actor with org root", %{
      organization_id: org_id
    } do
      requester = Fixtures.user_fixture(%{organization_id: org_id})
      Actor.put!(org_id, requester.id)

      # Exactly what would happen if the conventional worker preamble crept in above the loop.
      Repo.put_process_state(org_id)

      assert_raise Actor.Error, ~r/organization root user/, fn ->
        Actor.assert!(org_id, requester.id)
      end
    end

    # An organisation's root_user is its main account — a real person logs in as it, and in a
    # seeded dev org it is user 1, the default login. Treating "is root" as proof of a hijack
    # locked those users out of every tool-using skill. What the detector actually guards is
    # whether the acting identity is still the requester; root-ness only names the likely cause
    # when it is not.
    test "passes when the requester legitimately is the organization root user", %{
      organization_id: org_id
    } do
      root_user = Partners.organization(org_id).root_user
      Actor.put!(org_id, root_user.id)

      assert :ok == Actor.assert!(org_id, root_user.id)
    end

    test "fails if the acting user drifts", %{organization_id: org_id} do
      requester = Fixtures.user_fixture(%{organization_id: org_id})
      someone_else = Fixtures.user_fixture(%{organization_id: org_id})
      Actor.put!(org_id, someone_else.id)

      assert_raise Actor.Error, ~r/acting user drifted/, fn ->
        Actor.assert!(org_id, requester.id)
      end
    end

    test "fails when no actor was ever established" do
      # A fresh process has an empty process dictionary, which is the state an Oban job starts in.
      task = Task.async(fn -> catch_error(Actor.current!()) end)

      assert %Actor.Error{message: message} = Task.await(task)
      assert message =~ "no acting user"
    end
  end

  describe "permission model" do
    test "a restricted staff user is genuinely permission-filtered, root is not", %{
      organization_id: org_id
    } do
      restricted = Fixtures.user_fixture(%{organization_id: org_id})

      # User.changeset/2 demands password fields; this test only cares about the two flags that
      # drive skip_permission?/1.
      {:ok, restricted} =
        restricted
        |> Ecto.Changeset.change(%{is_restricted: true, roles: [:staff]})
        |> Repo.update()

      Actor.put!(org_id, restricted.id)

      refute Repo.skip_permission?(Repo.get_current_user()),
             "a restricted staff actor must not skip permission checks"

      root_user = Partners.organization(org_id).root_user

      assert Repo.skip_permission?(root_user),
             "org root skips permission checks — which is why the agent must not run as root"
    end
  end

  describe "with_actor/3" do
    test "establishes context for the duration of the function", %{organization_id: org_id} do
      requester = Fixtures.user_fixture(%{organization_id: org_id})

      result =
        Actor.with_actor(org_id, requester.id, fn ->
          Actor.assert!(org_id, requester.id)
          :did_the_work
        end)

      assert result == :did_the_work
    end
  end

  describe "source guard" do
    test "no module under lib/glific/ai/ calls Repo.put_process_state/1" do
      # actor.ex names the function in its docs and error messages — that is the point of it.
      offenders =
        "lib/glific/ai/**/*.ex"
        |> Path.wildcard()
        |> Enum.concat(Path.wildcard("lib/glific/ai.ex"))
        |> Enum.reject(&String.ends_with?(&1, "ai/actor.ex"))
        |> Enum.filter(&(File.read!(&1) =~ "put_process_state("))

      assert offenders == [],
             """
             These modules call Repo.put_process_state/1, which sets the current user to the
             organisation root and makes Repo.add_permission/3 a no-op. The agent must act as the
             requesting user — use Glific.AI.Actor.put!/2 instead.

             #{Enum.join(offenders, "\n")}
             """
    end
  end
end
