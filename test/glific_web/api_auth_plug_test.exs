defmodule GlificWeb.APIAuthPlugTest do
  use GlificWeb.ConnCase
  doctest GlificWeb.APIAuthPlug

  alias GlificWeb.{APIAuthPlug, Endpoint}
  alias Glific.{Repo, Users.User}

  @pow_config [otp_app: :glific]

  setup %{conn: conn} do
    conn = %{conn | secret_key_base: Endpoint.config(:secret_key_base)}
    user = Repo.insert!(%User{id: 1, phone: "+919820198765"})

    {:ok, conn: conn, user: user}
  end

  test "can create, fetch, renew, and delete session", %{conn: conn, user: user} do
    assert {_no_auth_conn, nil} = APIAuthPlug.fetch(conn, @pow_config)

    assert {%{private: %{api_access_token: access_token, api_renewal_token: renewal_token}},
            ^user} = APIAuthPlug.create(conn, user, @pow_config)

    :timer.sleep(100)

    assert {_conn, ^user} = APIAuthPlug.fetch(with_auth_header(conn, access_token), @pow_config)

    assert {%{
              private: %{
                api_access_token: renewed_access_token,
                api_renewal_token: renewed_renewal_token
              }
            }, ^user} = APIAuthPlug.renew(with_auth_header(conn, renewal_token), @pow_config)

    :timer.sleep(100)

    assert {_conn, nil} = APIAuthPlug.fetch(with_auth_header(conn, access_token), @pow_config)
    assert {_conn, nil} = APIAuthPlug.renew(with_auth_header(conn, renewal_token), @pow_config)

    assert {_conn, ^user} =
             APIAuthPlug.fetch(with_auth_header(conn, renewed_access_token), @pow_config)

    APIAuthPlug.delete(with_auth_header(conn, renewed_access_token), @pow_config)
    :timer.sleep(100)

    assert {_conn, nil} =
             APIAuthPlug.fetch(with_auth_header(conn, renewed_access_token), @pow_config)

    assert {_conn, nil} =
             APIAuthPlug.renew(with_auth_header(conn, renewed_renewal_token), @pow_config)
  end

  defp with_auth_header(conn, token), do: Plug.Conn.put_req_header(conn, "authorization", token)
end
