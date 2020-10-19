defmodule Glific.CSV.Menu do
  @moduledoc """
  Represent a menu interpreted from the CSV. Each Menu item either sends a content message
  or sends a sub-menu. A menu is an array of menu items
  """
  use Ecto.Schema

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          sr_no: integer() | nil,
          input: String.t() | nil,
          position: integer() | nil,
          parent: Ecto.UUID.t() | nil,
          content: map() | nil,
          menu_content: map() | nil,
          content_items: map() | nil,
          sub_menus: map() | nil
        }

  embedded_schema do
    field :uuid, Ecto.UUID

    field :sr_no, :integer

    # this is the input column or row, which made us create this record
    field :input, :string

    # the position of this menu item, when we are stiching the higher level
    # content together
    field :position, :integer

    # the content we send to render this menu. This is computed from
    # sub_menus, menu_content, and content_items
    # map to account for multiple languages
    field :content, :map

    field :parent, Ecto.UUID

    # this is one content item which stores the text of the menu in all languages
    field :menu_content, :map, virtual: true

    # this is an array of content items which stores each individual cell
    field :content_items, :map, virtual: true

    # this is an array of sub menu items for a top level menu
    field :sub_menus, :map, virtual: true
  end
end
