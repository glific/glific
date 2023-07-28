defmodule Glific.ExtensionTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Extensions.Extension,
    Fixtures
  }

  describe "extensions" do
    @valid_code """
    defmodule Glific.Test.Extension.Version do
      def current_version() do
        %{version: 1}
      end
    end
    """
    @valid_attrs %{
      code: @valid_code,
      is_active: true,
      module: "Glific.Test.Extension",
      name: "Test extension version"
    }
    @update_code """
    defmodule Glific.Test.Extension.VersionUpdate do
      def current_version() do
        %{version: 2}
      end
    end
    """
    @update_attrs %{
      is_active: false,
      code: @update_code
    }
    @invalid_attrs %{
      code: nil,
      is_active: nil,
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

    assert extension.code == @valid_code
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

    assert updated_extension.is_valid == nil
    assert updated_extension.name == "Current Version"

    assert updated_extension.code == @update_code
  end

  test "extension/1 deletes the extension", %{organization_id: organization_id} do
    extension = Fixtures.extension_fixture(%{organization_id: organization_id})
    assert {:ok, %Extension{}} = Extension.delete_extension(extension)
    assert true == is_nil(Extension.get_extension(%{id: extension.id}))
  end
end
