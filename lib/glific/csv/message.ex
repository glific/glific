defmodule Glific.CSV.Message do
  @moduledoc """
  Represents a message. We need to figure how to string a message from the contents. Seems like
  the best way, might be to let the NGO use a spreadsheet formula and we get the result directly
  in the CSV
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
