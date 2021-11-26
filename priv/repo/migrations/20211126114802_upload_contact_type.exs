defmodule Glific.Repo.Migrations.UploadContactType do
  use Ecto.Migration

  alias Glific.Enums.UploadContactsType

  def up do
    UploadContactsType.create_type()
  end

  def down do
    UploadContactsType.drop_type()
  end
end
