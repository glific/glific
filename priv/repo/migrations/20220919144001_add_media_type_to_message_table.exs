defmodule Glific.Repo.Migrations.AddMediaTypeToMessageTable do
  use Ecto.Migration

  alias Glific.Enums.MediaType

  def up do
    MediaType.create_type()
  end

  def down do
    MediaType.drop_type()
  end
end
