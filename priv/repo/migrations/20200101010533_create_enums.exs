defmodule Glific.Repo.Migrations.CreateEnums do
  use Ecto.Migration

  alias Glific.Enums.{
    APIStatus,
    ContactStatus,
    ContactProviderStatus,
    FlowCase,
    FlowRouter,
    FlowActionType,
    FlowType,
    MessageFlow,
    MessageType,
    MessageStatus,
    QuestionType,
    SortOrder,
    ContactFieldValueType,
    ContactFieldScope
  }

  def up do
    APIStatus.create_type()
    ContactStatus.create_type()
    ContactProviderStatus.create_type()
    FlowCase.create_type()
    FlowRouter.create_type()
    FlowActionType.create_type()
    FlowType.create_type()
    MessageFlow.create_type()
    MessageType.create_type()
    MessageStatus.create_type()
    QuestionType.create_type()
    SortOrder.create_type()
    ContactFieldValueType.create_type()
    ContactFieldScope.create_type()
  end

  def down do
    APIStatus.drop_type()
    ContactStatus.drop_type()
    ContactProviderStatus.drop_type()
    FlowCase.drop_type()
    FlowRouter.drop_type()
    FlowActionType.drop_type()
    FlowType.drop_type()
    MessageFlow.drop_type()
    MessageStatus.drop_type()
    MessageType.drop_type()
    QuestionType.drop_type()
    SortOrder.drop_type()
    ContactFieldValueType.drop_type()
    ContactFieldScope.drop_type()
  end
end
