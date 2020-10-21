defmodule Glific.CSV.Menu do
  @moduledoc """
  Represent a menu interpreted from the CSV. Each Menu item either sends a content message
  or sends a sub-menu. A menu is an array of menu items
  """
  use Ecto.Schema

  alias __MODULE__

  alias Glific.CSV.Content

  @type t() :: %__MODULE__{
          uuids: %{atom() => Ecto.UUID.t()} | nil,
          sr_no: integer() | nil,
          level: integer() | nil,
          position: integer() | nil,
          content: Content.t() | nil,
          menu_content: Content.t() | nil,
          content_item: Content.t() | nil,
          sub_menus: [Menu.t()] | nil
        }

  embedded_schema do
    # for now this includes:
    # main, node, action, router, exit, root and parent
    field :uuids, :map

    field :sr_no, :integer

    # The level of this menu item, helps us with layout
    field :level, :integer

    # the position of this menu item, when we are stitching the higher level
    # content together
    field :position, :integer

    # the content for this specific menu item. We add footers, headers and other extra stuff
    # to make the final content
    embeds_one :menu_content, Content

    # this os the content items for a leaf menu item that we send out when activated
    embeds_one :content_item, Content

    # this is an array of sub menu items for a top level menu
    embeds_many :sub_menus, Menu

    # the content we send to render this menu. This is computed from
    # sub_menus, menu_content, and content_items
    # and merged into a map, with keys for each language
    field :content, :map
  end
end
