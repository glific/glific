defmodule GlificWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use GlificWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  alias Glific.{
    Fixtures,
    Repo
  }

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import GlificWeb.ConnCase

      alias GlificWeb.Router.Helpers, as: Routes

      # The default endpoint for testing
      @endpoint GlificWeb.Endpoint

      defmacro auth_query_gql_by(query, user, options \\ []) do
        quote do
          options_user =
            Keyword.put_new(unquote(options), :context, %{:current_user => unquote(user)})

          query_gql_by(unquote(query), options_user)
        end
      end
    end
  end

  setup tags do
    :ok = Sandbox.checkout(Repo)

    unless tags[:async] do
      Sandbox.mode(Repo, {:shared, self()})
    end

    # organization_id = Fixtures.get_org_id()
    organization_id = 1

    {
      :ok,
      conn: Phoenix.ConnTest.build_conn() |> Plug.Conn.assign(:organization_id, organization_id),
      organization_id: organization_id,
      user: Fixtures.user_fixture(),
      manager: Fixtures.user_fixture(%{roles: ["manager"]}),
      staff: Fixtures.user_fixture(%{roles: ["staff"]}),
      glific_admin: Fixtures.user_fixture(%{roles: ["glific_admin"]})
    }
  end
end
