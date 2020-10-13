defmodule Glific.CSV.Menu do
  @moduledoc """
  Represent a menu interpreted from the CSV. Each Menu item either sends a content message
  or sends a sub-menu. A menu is an array of menu items
  """

  alias Glific.{
    CSV.File,
    CSV.MenuItems,
    CSV.Message,
  }

  @type t() :: %__MODULE__{
    uuid: Ecto.UUID.t() | nil,
    sr_no: integer() | nil,
    input: String.t() | nil
    menu_items: [MenuItem.t()] | nil,
    parent: File.t() | nil,
  }

  embedded_schema do
    field :uuid, Ecto.UUID

    field :sr_no, :integer
    field :input, :string

    belongs_to :parent, File

    embeds_many :menu_items, MenuItem
  end
end
