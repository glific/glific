defmodule Glific.Repo.Migrations.CreateEnums do
  use Ecto.Migration

  alias Glific.{
    APIStatusEnum,
    ContactStatusEnum,
    MessageFlowEnum,
    MessageTypesEnum,
    MessageStatusEnum,
    SortOrderEnum
  }

  def up do
    APIStatusEnum.create_type()
    ContactStatusEnum.create_type()
    MessageFlowEnum.create_type()
    MessageTypesEnum.create_type()
    MessageStatusEnum.create_type()
    SortOrderEnum.create_type()
  end

  def down do
    APIStatusEnum.drop_type()
    ContactStatusEnum.drop_type()
    MessageFlowEnum.drop_type()
    MessageStatusEnum.drop_type()
    MessageTypesEnum.drop_type()
    SortOrderEnum.drop_type()
  end
end
