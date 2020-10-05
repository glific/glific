defmodule Glific.Repo.Migrations.AlterEnums do
  use Ecto.Migration

  alias Glific.Enums.{
    ContactBspStatus
  }

  def up do
    ContactBspStatus.create_type()
  end

  def down do
    ContactBspStatus.drop_type()
  end
end
