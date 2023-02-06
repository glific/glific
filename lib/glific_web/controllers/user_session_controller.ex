defmodule GlificWeb.UserSessionController do
  use GlificWeb, :controller

  alias Glific.Accounts
  alias GlificWeb.UserAuth

  def new(conn, _params) do
    render(conn, "new.html", error_message: nil)
  end

  def create(conn, %{"user" => user_params}) do
    %{"phone" => phone, "password" => password} = user_params

    if user = Accounts.get_user_by_phone_and_password(phone, password) do
      UserAuth.log_in_user(conn, user, user_params)
      |> IO.inspect()
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      render(conn, "new.html", error_message: "Invalid email or password")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
