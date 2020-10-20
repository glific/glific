defmodule Glific.CSV.Content do
  @moduledoc """
  Represent a menu interpreted from the CSV. Each Menu item either sends a content message
  or sends a sub-menu. A menu is an array of menu items
  """
  use Ecto.Schema

  @type t() :: %__MODULE__{
          sr_no: integer() | nil,
          position: integer() | nil,
          content: map() | nil
        }

  embedded_schema do
    field :sr_no, :integer

    # the position of this menu item, when we are stiching the higher level
    # content together
    field :position, :integer

    # the content we send to render this element. This is computed from
    # sub_menus, menu_content, and content_items
    # map to account for multiple languages
    field :content, :map
  end
end
