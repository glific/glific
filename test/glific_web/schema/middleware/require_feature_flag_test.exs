defmodule GlificWeb.Schema.Middleware.RequireFeatureFlagTest do
  use Glific.DataCase

  alias GlificWeb.Schema.Middleware.RequireFeatureFlag

  describe "call/2" do
    test "returns resolution unchanged when feature flag is enabled for the organization" do
      organization_id = 1

      FunWithFlags.enable(:ai_evaluations,
        for_actor: %{organization_id: organization_id}
      )

      user = %{organization_id: organization_id}
      resolution = %Absinthe.Resolution{context: %{current_user: user}}

      result =
        RequireFeatureFlag.call(resolution, {:ai_evaluations, "Feature not enabled."})

      assert result == resolution
      assert result.state != :resolved
    end

    test "returns error when feature flag is disabled for the organization" do
      organization_id = 1

      FunWithFlags.disable(:ai_evaluations,
        for_actor: %{organization_id: organization_id}
      )

      user = %{organization_id: organization_id}
      resolution = %Absinthe.Resolution{context: %{current_user: user}}

      result =
        RequireFeatureFlag.call(resolution, {:ai_evaluations, "AI Evaluations feature is not enabled for the organization."})

      assert result.state == :resolved
      assert [error_msg | _] = result.errors
      assert error_msg =~ "AI Evaluations feature is not enabled for the organization"
      assert result.context[:feature_flag_forbidden] == true
    end

    test "returns error when current_user is missing from context" do
      resolution = %Absinthe.Resolution{context: %{}}

      result =
        RequireFeatureFlag.call(resolution, {:ai_evaluations, "Feature not enabled."})

      assert result.state == :resolved
      assert [error_msg | _] = result.errors
      assert error_msg =~ "Feature not enabled"
    end
  end
end
