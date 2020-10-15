defmodule Glific.CSV.Menu do
  @moduledoc """
  Represent a menu interpreted from the CSV. Each Menu item either sends a content message
  or sends a sub-menu. A menu is an array of menu items
  """
  use Ecto.Schema

  alias Glific.{
    CSV.File,
    CSV.MenuItems,
    CSV.Message,
  }

  @type t() :: %__MODULE__{
    uuid: Ecto.UUID.t() | nil,
    sr_no: integer() | nil,
    input: String.t() | nil,
    content: String.t() | nil,
    menu_items: [MenuItem.t()] | nil,
    parent: File.t() | nil,
  }

  embedded_schema do
    field :uuid, Ecto.UUID

    field :sr_no, :integer

    # this is the input column or row, which made us create this record
    field :input, :string

    # The name of this menu. We'll always call the top level menu
    # "Main Menu"
    field :title, :string

    # the position of this menu item, when we are stiching the higher level
    # content together
    field :position, :integer

    # the content we send to render this menu
    field :content, :string

    belongs_to :parent, Menu

    embeds_many :menu_items, Menu
    embeds_many :content_items, Content
  end
end
