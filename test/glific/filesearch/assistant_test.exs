defmodule Glific.Filesearch.AssistantTest do
  @moduledoc """
  Tests for Assistants
  """
  alias Glific.Filesearch.Assistant
  use GlificWeb.ConnCase

  test "create_assistant/1 with valid data creates an assistant", attrs do
    valid_attrs = %{
      assistant_id: "asst_abc",
      name: "temp assistant",
      model: "gpt-4o",
      temperature: 1,
      organization_id: attrs.organization_id
    }

    assert {:ok, _assistant} = Assistant.create_assistant(valid_attrs)
  end

  test "create_assistant/1 with invalid data not create an assistant", attrs do
    valid_attrs = %{
      assistant_id: "asst_abc",
      name: "temp assistant",
      model: "gpt-4o",
      organization_id: attrs.organization_id
    }

    assert {:error, _} = Assistant.create_assistant(valid_attrs)
  end

  test "get_assistant/1 with valid id returns an assistant", attrs do
    valid_attrs = %{
      assistant_id: "asst_abc",
      name: "temp assistant",
      model: "gpt-4o",
      temperature: 1,
      organization_id: attrs.organization_id
    }

    assert {:ok, assistant} = Assistant.create_assistant(valid_attrs)

    assert {:ok, %Assistant{}} = Assistant.get_assistant(assistant.id)
  end

  test "get_assistant/1 with invalid id not return an assistant", _attrs do
    assert {:error, _} = Assistant.get_assistant(0)
  end

  test "list_assistants/1 returns list of assistants matching the filters", attrs do
    valid_attrs = %{
      assistant_id: "asst_abc",
      name: "temp assistant",
      model: "gpt-4o",
      temperature: 1,
      organization_id: attrs.organization_id
    }

    assert {:ok, _assistant} = Assistant.create_assistant(valid_attrs)

    valid_attrs = %{
      assistant_id: "asst_def",
      name: "assistant 2",
      model: "gpt-4o",
      temperature: 1,
      organization_id: attrs.organization_id
    }

    assert {:ok, _assistant} = Assistant.create_assistant(valid_attrs)

    assert [assistant] = Assistant.list_assistants(%{filter: %{name: "temp"}})
    assert assistant.name == "temp assistant"
  end

  test "update_assistants/1 updates assistant", attrs do
    valid_attrs = %{
      assistant_id: "asst_abc",
      name: "temp assistant",
      model: "gpt-4o",
      temperature: 1,
      organization_id: attrs.organization_id
    }

    assert {:ok, assistant} = Assistant.create_assistant(valid_attrs)

    valid_attrs = %{
      name: "assistant 3"
    }

    assert {:ok, assistant} = Assistant.update_assistant(assistant, valid_attrs)
    assert assistant.assistant_id == "asst_abc"
    assert assistant.name == "assistant 3"
  end
end
