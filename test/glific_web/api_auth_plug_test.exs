defmodule GlificWeb.APIAuthPlugTest do
  use GlificWeb.ConnCase
  doctest GlificWeb.APIAuthPlug

  alias GlificWeb.{APIAuthPlug, Endpoint}

  alias Glific.{
    Fixtures,
    Repo,
    Users.User
  }

  @pow_config [otp_app: :glific]

  setup %{conn: conn} do
    contact = Fixtures.contact_fixture()

    conn = %{conn | secret_key_base: Endpoint.config(:secret_key_base)}

    user =
      Repo.insert!(%User{
        phone: "+919820198766",
        contact_id: contact.id,
        organization_id: contact.organization_id
      })

    {:ok, conn: conn, user: user}
  end

  test "can create, fetch, renew, and delete session", %{conn: conn, user: user} do
    assert {_no_auth_conn, nil} = APIAuthPlug.fetch(conn, @pow_config)

    {data, api_user} = APIAuthPlug.create(conn, user, @pow_config)
    assert Map.has_key?(api_user, :fingerprint)
    assert !is_nil(api_user.fingerprint)
    assert %{private: %{api_access_token: access_token, api_renewal_token: renewal_token}} = data
    assert Map.delete(user, :fingerprint) == Map.delete(api_user, :fingerprint)

    :timer.sleep(100)

    {_conn, api_user} = APIAuthPlug.fetch(with_auth_header(conn, access_token), @pow_config)
    assert Map.has_key?(api_user, :fingerprint)
    assert !is_nil(api_user.fingerprint)
    assert Map.delete(user, :fingerprint) == Map.delete(api_user, :fingerprint)

    assert {%{
              private: %{
                api_access_token: renewed_access_token,
                api_renewal_token: renewed_renewal_token
              }
            }, _api_user} = APIAuthPlug.renew(with_auth_header(conn, renewal_token), @pow_config)

    :timer.sleep(100)

    assert {_conn, nil} = APIAuthPlug.fetch(with_auth_header(conn, access_token), @pow_config)
    assert {_conn, nil} = APIAuthPlug.renew(with_auth_header(conn, renewal_token), @pow_config)

    {_conn, api_user} =
      APIAuthPlug.fetch(with_auth_header(conn, renewed_access_token), @pow_config)

    assert Map.has_key?(api_user, :fingerprint)
    assert !is_nil(api_user.fingerprint)
    assert Map.delete(user, :fingerprint) == Map.delete(api_user, :fingerprint)

    APIAuthPlug.delete(with_auth_header(conn, renewed_access_token), @pow_config)
    :timer.sleep(100)

    assert {_conn, nil} =
             APIAuthPlug.fetch(with_auth_header(conn, renewed_access_token), @pow_config)

    assert {_conn, nil} =
             APIAuthPlug.renew(with_auth_header(conn, renewed_renewal_token), @pow_config)
  end

  defp with_auth_header(conn, token), do: Plug.Conn.put_req_header(conn, "authorization", token)

  test "delete all existing sessions of a user", %{conn: conn, user: user} do
    {data, api_user} = APIAuthPlug.create(conn, user, @pow_config)
    assert Map.has_key?(api_user, :fingerprint)
    assert !is_nil(api_user.fingerprint)
    assert %{private: %{api_access_token: access_token, api_renewal_token: _renewal_token}} = data
    assert Map.delete(user, :fingerprint) == Map.delete(api_user, :fingerprint)

    {data, api_user} = APIAuthPlug.create(conn, user, @pow_config)
    assert Map.has_key?(api_user, :fingerprint)

    assert %{private: %{api_access_token: access_token2, api_renewal_token: _renewal_token2}} =
             data

    assert Map.delete(user, :fingerprint) == Map.delete(api_user, :fingerprint)

    :timer.sleep(100)

    {conn, api_user} = APIAuthPlug.fetch(with_auth_header(conn, access_token), @pow_config)
    assert Map.has_key?(api_user, :fingerprint)
    assert !is_nil(api_user.fingerprint)
    assert Map.delete(user, :fingerprint) == Map.delete(api_user, :fingerprint)

    {conn, api_user} = APIAuthPlug.fetch(with_auth_header(conn, access_token2), @pow_config)
    assert Map.has_key?(api_user, :fingerprint)
    assert !is_nil(api_user.fingerprint)
    assert Map.delete(user, :fingerprint) == Map.delete(api_user, :fingerprint)

    APIAuthPlug.delete_all_user_sessions(@pow_config, user)

    :timer.sleep(100)

    # existing sessions should be deleted
    assert {_conn, nil} = APIAuthPlug.fetch(with_auth_header(conn, access_token), @pow_config)
    assert {_conn, nil} = APIAuthPlug.fetch(with_auth_header(conn, access_token2), @pow_config)
  end
end
