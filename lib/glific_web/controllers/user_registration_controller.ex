defmodule GlificWeb.UserRegistrationController do
  use GlificWeb, :controller

  alias Glific.Accounts
  alias Glific.Users.User
  alias GlificWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    render(conn, "new.html", changeset: changeset)
  end

  @spec create(Plug.Conn.t(), map) :: {:ok, any} | Plug.Conn.t()
  def create(conn, %{"user" => user_params}) do
    # TODO: fix user registration

    # user_params =
    #   user_params
    #   |> Map.merge(%{
    #     "contact_id" => 1,
    #     "organization_id" => 1,
    #     "language_id" => 1,
    #     "password_confirmation" => user_params["password"],
    #     "name" => user_params["phone"]
    #   })

    Accounts.register_user(user_params)
    |> case do
      {:ok, user} ->
        # Accounts.deliver_user_confirmation_instructions(
        #   user,
        #   &Routes.user_confirmation_url(conn, :edit, &1)
        # )
        conn
        |> put_flash(:info, "User created successfully.")
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end
end
