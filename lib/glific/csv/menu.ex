defmodule Glific.CSV.Menu do
  @moduledoc """
  Represent a menu interpreted from the CSV. Each Menu item either sends a content message
  or sends a sub-menu. A menu is an array of menu items
  """
  use Ecto.Schema

  alias __MODULE__

  alias Glific.CSV.Content

  @type t() :: %__MODULE__{
          uuid: Ecto.UUID.t() | nil,
          sr_no: integer() | nil,
          position: integer() | nil,
          level: integer() | nil,
          root: Ecto.UUID.t() | nil,
          parent: Ecto.UUID.t() | nil,
          content: Content.t() | nil,
          menu_content: Content.t() | nil,
          content_items: [Content.t()] | nil,
          sub_menus: [Menu.t()] | nil
        }

  embedded_schema do
    field :uuid, Ecto.UUID

    field :sr_no, :integer

    # the position of this menu item, when we are stiching the higher level
    # content together
    field :position, :integer

    # The level of this menu item, helps us with layout
    field :level, :integer

    # The root of this flow
    field :root, Ecto.UUID

    # The menu i've come from, useful when we implement previous menu
    # functionality
    field :parent, Ecto.UUID

    # the content for this specific menu item. We add footers, headers and other extra stuff
    # to make the final content
    embeds_one :menu_content, Content

    # this is an array of content items which stores each individual cell
    embeds_many :content_items, Content

    # this is an array of sub menu items for a top level menu
    embeds_many :sub_menus, Menu

    # the content we send to render this menu. This is computed from
    # sub_menus, menu_content, and content_items
    # and merged into one content object
    embeds_one :content, Content
  end
end
