defmodule Glific.Clients.Lahi do
  @moduledoc """
    Implementation for the Lahi
  """
  alias Glific.{
    Contacts,
    Flows.ContactField,
    Groups,
    Groups.Group,
    Repo
  }
  @doc """
    In the case of LAHI we retrive image and will fromat the name of the image
  """
  def webhook("save_internship_image", fields) do
    # implementation need to be add here
  end
end
