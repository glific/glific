defmodule Glific.ConfigTest do
  use ExUnit.Case

  import Dotenvy
  @tag :dotenv
  test "dotenvy source now needs explicitly set system_env" do
    System.put_env("DB_URL", "url")
    {:ok, _} = source([])

    # In 0.8.0 doing env!("DB_URL", :string!) returns "url"
    # But in 0.9.0 it removed this auto fallback to System.fetch_env as mentioned
    # https://hexdocs.pm/dotenvy/changelog.html#v0-9-0

    assert_raise(RuntimeError, fn -> env!("DB_URL", :string!) end)

    # explicitly fetching system_env
    {:ok, _} = source([System.get_env()])
    assert "url" == env!("DB_URL", :string!)
  end
end
