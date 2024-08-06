defmodule Glific.GigalixirTest do
  @moduledoc """
  Tests for Glific.Gigalixir
  """
  use Glific.DataCase
  alias Glific.Gigalixir

  test "Failed create_domain due to invalid shortcode" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 404,
          body: %{
            data: %{cname: "+++.glific.com.giglixirdns.com"}
          }
        }
    end)

    invalid_shortcode = "+++"

    assert {:error, _} = Gigalixir.create_domain(invalid_shortcode)
  end

  test "Valid create_domain" do
    Tesla.Mock.mock(fn
      %{method: :post} ->
        %Tesla.Env{
          status: 201,
          body: %{
            data: %{cname: "example.glific.com.giglixirdns.com"}
          }
        }
    end)

    valid_shortcode = "example"

    assert {:ok, "Domain successfully created!"} = Gigalixir.create_domain(valid_shortcode)
  end
end
