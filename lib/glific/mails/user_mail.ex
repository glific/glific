defmodule Glific.Mails.UserEmail do
  import Swoosh.Email

  defp sender() do
    {"Pankaj Agrawal", "glific-tides@coloredcow.com"}
  end

  def welcome(user) do
    new()
    |> to({user.name, user.email})
    |> from(sender())
    |> subject("Hello, Avengers!")
    |> html_body("<h1>Hello #{user.name}</h1>")
    |> text_body("Hello #{user.name}\n")
  end
end
