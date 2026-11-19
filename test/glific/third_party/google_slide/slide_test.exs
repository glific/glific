defmodule Glific.ThirdParty.GoogleSlide.SlideTest do
  use ExUnit.Case, async: true

  alias Glific.ThirdParty.GoogleSlide.Slide

  doctest Slide

  @presentation_url "https://docs.google.com/presentation/d/1qHobEu0HbRHpiHJbqAEvu_M13YvJ1qWIWiAcWXXXBFk/edit"
  @presentation_id "1qHobEu0HbRHpiHJbqAEvu_M13YvJ1qWIWiAcWXXXBFk"

  describe "parse_slides_url/1" do
    test "accepts slide ids starting with g" do
      assert {:ok, %{presentation_id: @presentation_id, page_id: "gc6f9fe735_0_0"}} =
               Slide.parse_slides_url("#{@presentation_url}#slide=id.gc6f9fe735_0_0")
    end

    test "accepts slide ids with other prefixes, including - and _" do
      assert {:ok, %{presentation_id: @presentation_id, page_id: "h5354e71374cd0ed6_14_0"}} =
               Slide.parse_slides_url(
                 "#{@presentation_url}?slide=id.h5354e71374cd0ed6_14_0#slide=id.h5354e71374cd0ed6_14_0"
               )

      assert {:ok, %{page_id: "SLIDES_API-123_0"}} =
               Slide.parse_slides_url("#{@presentation_url}#slide=id.SLIDES_API-123_0")
    end

    test "accepts the slide id in either the query or the fragment" do
      assert {:ok, %{page_id: "h5354e71374cd0ed6_14_0"}} =
               Slide.parse_slides_url("#{@presentation_url}?slide=id.h5354e71374cd0ed6_14_0")

      assert {:ok, %{page_id: "h5354e71374cd0ed6_14_0"}} =
               Slide.parse_slides_url("#{@presentation_url}#slide=id.h5354e71374cd0ed6_14_0")
    end

    test "rejects the id.p placeholder" do
      assert {:error, "Template url not a valid Google Slides url"} =
               Slide.parse_slides_url("#{@presentation_url}#slide=id.p")

      assert {:error, "Template url not a valid Google Slides url"} =
               Slide.parse_slides_url("#{@presentation_url}?slide=id.p#slide=id.p")
    end

    test "rejects urls without a slide id or a presentation id" do
      assert {:error, _} = Slide.parse_slides_url(@presentation_url)
      assert {:error, _} = Slide.parse_slides_url("https://example.com/edit#slide=id.g123")
    end
  end
end
