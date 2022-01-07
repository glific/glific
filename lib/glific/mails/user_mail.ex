defmodule Glific.Mails.UserEmail do
  import Swoosh.Email
  alias Glific.Communications.Mailer

  def welcome(user) do
    new()
    |> to({user.name, user.email})
    |> from(Mailer.sender())
    |> subject("Hello, New Organization Added")
    |> html_body("<h1>Hello #{user.name}</h1>")
    |> text_body("Hello #{user.name}\n")
  end
end
