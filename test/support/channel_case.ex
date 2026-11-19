defmodule GlificWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.

  Such tests rely on `Phoenix.ChannelTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use GlificWeb.ChannelCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Glific.{Fixtures, Partners, Repo, WebChannelFlagHelpers}

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import GlificWeb.ChannelCase

      alias Glific.WebChannelFixtures

      # The default endpoint for testing
      @endpoint GlificWeb.Endpoint
    end
  end

  setup tags do
    :ok = Sandbox.checkout(Repo)

    unless tags[:async] do
      Sandbox.mode(Repo, {:shared, self()})
    end

    Repo.put_organization_id(1)
    Repo.put_current_user(Fixtures.user_fixture(%{name: "NGO Test Admin", roles: ["manager"]}))

    organization_id = 1
    organization_id |> Partners.get_organization!() |> Partners.fill_cache()
    WebChannelFlagHelpers.reset_web_channel_flag(organization_id)

    %{organization_id: organization_id}
  end

  defdelegate reset_web_channel_flag(organization_id \\ 1), to: WebChannelFlagHelpers
  defdelegate with_web_channel_enabled(organization_id \\ 1, fun), to: WebChannelFlagHelpers
end
