defmodule Glific.Repo.Migrations.ImportContactType do
  use Ecto.Migration

  alias Glific.Enums.ImportContactsType

  def up do
    ImportContactsType.create_type()
  end

  def down do
    ImportContactsType.drop_type()
  end
end
