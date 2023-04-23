defmodule GlificWeb.UserSessionController do
  @moduledoc """
  A controller to manage user sessions.
  We might need to move this logic to glific old sessions controller which we are using for pow.
  """

  use GlificWeb, :controller

  alias Glific.Accounts
  alias GlificWeb.UserAuth

  @doc """
    Show new login screen
  """
  @spec new(Plug.Conn.t(), map()) :: any()
  def new(conn, _params) do
    render(conn, "new.html", error_message: nil)
  end

  @doc """
    Create new user session
  """
  @spec create(Plug.Conn.t(), map()) :: any()
  def create(conn, %{"user" => user_params}) do
    %{"phone" => phone, "password" => password} = user_params

    if user = Accounts.get_user_by_phone_and_password(phone, password) do
      UserAuth.log_in_user(conn, user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      render(conn, "new.html", error_message: "Invalid email or password")
    end
  end

  @doc """
    Delete all the user sessions. (Logout)
  """
  @spec delete(Plug.Conn.t(), map()) :: any()
  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
