defmodule Glific.MessageVariablesTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo

  alias Glific.Messages.MessageVariables

  describe "message variables" do
    test "get global field map should return a map" do
      map = MessageVariables.get_global_field_map()
      assert map == :error

      Application.put_env(:glific, :app_base_url, "test_url")
      map = MessageVariables.get_global_field_map()
      assert map[:registration] != nil
    end
  end
end
