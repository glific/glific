defmodule Glific.Repo.Migrations.CreateEnums do
  use Ecto.Migration

  alias Glific.Enums.{
    APIStatus,
    ContactStatus,
    MessageFlow,
    MessageType,
    MessageStatus,
    QuestionType,
    SortOrder
  }

  def up do
    APIStatus.create_type()
    ContactStatus.create_type()
    MessageFlow.create_type()
    MessageType.create_type()
    MessageStatus.create_type()
    QuestionType.create_type()
    SortOrder.create_type()
  end

  def down do
    APIStatus.drop_type()
    ContactStatus.drop_type()
    MessageFlow.drop_type()
    MessageStatus.drop_type()
    MessageType.drop_type()
    QuestionType.drop_type()
    SortOrder.drop_type()
  end
end
