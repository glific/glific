defmodule Glific.ExtensionTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Extensions.Extension,
    Fixtures
  }

  describe "extensions" do
    @valid_attrs %{
      code:
        "defmodule Glific.Test.Extension.Version, do: def current_verion(), do: %{version: 1}",
      isActive: true,
      module: "Glific.Test.Extension",
      name: "Test extension version"
    }
    # @valid_more_attrs %{
    #   code: "defmodule Glific.Test.Extension.Id, do: def current_id(), do: %{id: 22194}",
    #   isActive: true,
    #   module: "Glific.Test.Extension.Id",
    #   name: "Test extension id"
    # }
    @update_attrs %{
      isActive: false,
      code: "defmodule Glific.Test.Extension.Version, do: def current_verion(), do: %{version: 2}"
    }
    @invalid_attrs %{
      code: nil,
      isActive: nil,
      module: nil,
      name: nil
    }
  end

  test "create_extension/1 with valid data creates a extension", %{
    organization_id: organization_id
  } do
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

    assert {:ok, %Extension{} = extension} = Extension.create_extension(attrs)
    assert extension.is_active == true
    assert extension.is_valid == true
    assert extension.name == "Test extension version"

    assert extension.code ==
             "defmodule Glific.Test.Extension.Version, do: def current_verion(), do: %{version: 1}"
  end

  test "create_extension/1 with invalid data returns error changeset", %{
    organization_id: organization_id
  } do
    attrs = Map.merge(@invalid_attrs, %{organization_id: organization_id})

    assert {:error, %Ecto.Changeset{}} = Extension.create_extension(attrs)
  end

  test "update_extension/2 with valid data updates the extension", %{
    organization_id: organization_id
  } do
    attrs = Map.merge(@valid_attrs, %{organization_id: organization_id})

    assert {:ok, %Extension{} = extension} = Extension.create_extension(attrs)

    attrs = Map.merge(@update_attrs, %{name: "Current Version"})

    assert {:ok, %Extension{} = updated_extension} = Extension.update_extension(extension, attrs)

    assert updated_extension.is_valid == true
    assert updated_extension.name == "Current Version"

    assert updated_extension.code ==
             "defmodule Glific.Test.Extension.Version, do: def current_verion(), do: %{version: 2}"
  end

  test "extension/1 deletes the extension", %{organization_id: organization_id} do
    extension = Fixtures.extension_fixture(%{organization_id: organization_id})
    assert {:ok, %Extension{}} = Extension.delete_extension(extension)
    assert true == is_nil(Extension.get_extension(%{id: extension.id}))
  end
end
