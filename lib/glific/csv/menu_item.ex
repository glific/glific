defmodule Glific.CSV.MenuItem do
  @moduledoc """
  Represent a menu item. Each item is either a content message or a sub-menu
  (which is also a message, but a special type of message)
  """

  alias Glific.{
    CSV.Menu
  }

  @type t() :: %__MODULE__{
    uuid: Ecto.UUID.t() | nil,
    sr_no: integer() | nil,
    input: String.t() | nil
    message: Message.t() | nil,
    menu: Menu.t() | nil,
  }

  embedded_schema do
    field :uuid, Ecto.UUID

    field :sr_no, :integer
    field :input, :string

    field :message, String
    field :menu, Menu

    belongs_to :parent, Menu
  end
end
