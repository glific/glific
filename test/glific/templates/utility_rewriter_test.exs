defmodule Glific.Templates.UtilityRewriterTest do
  @moduledoc false
  # `Glific.AI.Model.Stub` is a globally-named Agent shared across test files — async: true
  # would leak one file's queued responses into another's assertions.
  use Glific.DataCase, async: false

  alias Glific.AI.Model.Stub
  alias Glific.Fixtures
  alias Glific.Templates.UtilityRewriter

  @draft %{
    body: "Hi {{1}}, your appointment at the {{2}} clinic is confirmed.",
    footer: "Reply STOP to opt out",
    buttons: ["Confirm", "Reschedule"],
    label: "Appointment confirmation"
  }

  # Glific.AI.Run.sync/3 honours the skill's own feature_flag/0, and every flag is seeded
  # disabled for a new organisation (Glific.Misc.Flags), so this precondition is what the whole
  # file depends on rather than something incidental.
  setup %{organization_id: organization_id} do
    start_supervised!(Stub)

    FunWithFlags.enable(:is_template_utility_rewrite_enabled,
      for_actor: %{organization_id: organization_id}
    )

    user = Fixtures.user_fixture(%{organization_id: organization_id})
    %{user: user}
  end

  defp queue_success(body, category \\ "UTILITY", changes \\ []) do
    Stub.queue_text("draft")

    Stub.queue_object(%{
      "body" => body,
      "suggested_category" => category,
      "changes" => changes
    })
  end

  describe "rewrite/2 — happy path" do
    test "returns the rewritten body, category and changes", %{user: user} do
      queue_success(@draft.body)

      assert {:ok, result} = UtilityRewriter.rewrite(@draft, user)
      assert result.body == @draft.body
      assert result.suggested_category == "UTILITY"
      assert result.changes == []
    end

    test "shapes each change into an atom-keyed map", %{user: user} do
      queue_success(@draft.body, "UTILITY", [
        %{
          "what_changed" => "Removed the exclamation mark",
          "why" => "Utility templates should read calmly, not persuasively",
          "best_practice" => "Avoid urgency and hype in utility copy",
          "best_practice_url" => "https://developers.facebook.com/docs/whatsapp"
        }
      ])

      assert {:ok, %{changes: [change]}} = UtilityRewriter.rewrite(@draft, user)
      assert change.what_changed == "Removed the exclamation mark"
      assert change.why == "Utility templates should read calmly, not persuasively"
      assert change.best_practice == "Avoid urgency and hype in utility copy"
      assert change.best_practice_url == "https://developers.facebook.com/docs/whatsapp"
    end

    test "a change entry may omit best_practice_url", %{user: user} do
      queue_success(@draft.body, "UTILITY", [
        %{
          "what_changed" => "Tightened the wording",
          "why" => "Shorter is clearer",
          "best_practice" => "Keep utility messages brief"
        }
      ])

      assert {:ok, %{changes: [change]}} = UtilityRewriter.rewrite(@draft, user)
      assert change.best_practice_url == nil
    end
  end

  describe "rewrite/2 — variable set preservation" do
    test "rejects a rewrite that drops a variable", %{user: user} do
      queue_success("Hi {{1}}, your appointment is confirmed.")
      queue_success("Hi {{1}}, your appointment is confirmed.")

      assert {:error, [%{key: "body", message: message}]} = UtilityRewriter.rewrite(@draft, user)
      assert message =~ "{{n}} placeholders"
    end

    test "rejects a rewrite that reorders variables", %{user: user} do
      swapped = "Hi {{2}}, your appointment at the {{1}} clinic is confirmed."
      queue_success(swapped)
      queue_success(swapped)

      assert {:error, [%{key: "body", message: _message}]} = UtilityRewriter.rewrite(@draft, user)
    end

    test "rejects a rewrite that introduces a new variable", %{user: user} do
      extra = "Hi {{1}}, your appointment at the {{2}} clinic on {{3}} is confirmed."
      queue_success(extra)
      queue_success(extra)

      assert {:error, [%{key: "body", message: _message}]} = UtilityRewriter.rewrite(@draft, user)
    end
  end

  describe "rewrite/2 — character budget" do
    test "rejects a rewrite over the 1024 character budget", %{user: user} do
      too_long =
        "Hi {{1}}, your appointment at the {{2}} clinic is confirmed. " <>
          String.duplicate("x", 1000)

      queue_success(too_long)
      queue_success(too_long)

      assert {:error, [%{key: "body", message: message}]} = UtilityRewriter.rewrite(@draft, user)
      assert message =~ "1024 characters"
    end
  end

  describe "rewrite/2 — category whitelist" do
    test "rejects a suggested_category outside the whitelist", %{user: user} do
      queue_success(@draft.body, "PROMOTIONAL")
      queue_success(@draft.body, "PROMOTIONAL")

      assert {:error, [%{key: "body", message: message}]} = UtilityRewriter.rewrite(@draft, user)
      assert message =~ "suggested_category must be one of"
    end
  end

  describe "rewrite/2 — bounded retry" do
    test "recovers when the first attempt violates a check but the retry does not", %{user: user} do
      queue_success("Hi {{1}}, confirmed.")
      queue_success(@draft.body)

      assert {:ok, result} = UtilityRewriter.rewrite(@draft, user)
      assert result.body == @draft.body
      assert length(Stub.calls()) == 4
    end

    test "a second violation is returned as an error rather than retried again", %{user: user} do
      queue_success("Hi {{1}}, confirmed.")
      queue_success("Hi {{1}}, confirmed.")

      assert {:error, _errors} = UtilityRewriter.rewrite(@draft, user)
      assert length(Stub.calls()) == 4
    end

    test "the retry's message includes the violation reason fed back to the model", %{user: user} do
      queue_success("Hi {{1}}, confirmed.")
      queue_success(@draft.body)

      assert {:ok, _result} = UtilityRewriter.rewrite(@draft, user)

      # Stub.calls/0 records every chat/2 and object/3 call, oldest first: the failing
      # attempt's [chat, object], then the retry's [chat, object] — the retry's chat call is
      # what carries the fed-back violation reason as the conversation's user message.
      [_first_chat, _first_object, retry_chat, _retry_object] = Stub.calls()
      retry_message = Enum.find(retry_chat.messages, &(&1.role == :user))
      retry_text = retry_message.content |> Enum.map_join("", & &1.text)

      assert retry_text =~ "PREVIOUS ATTEMPT REJECTED"
      assert retry_text =~ "{{n}} placeholders"
    end
  end

  describe "rewrite/2 — model failure" do
    test "a model error surfaces as a user-facing error, not a crash", %{user: user} do
      Stub.queue_error(%{status: 500, reason: "boom"})

      assert {:error, [%{key: "body", message: message}]} = UtilityRewriter.rewrite(@draft, user)
      refute message =~ "boom"
      assert length(Stub.calls()) == 1
    end
  end

  describe "rewrite/2 — upfront button validation (no model call)" do
    test "rejects button text longer than 20 characters without calling the model", %{
      user: user
    } do
      draft = %{@draft | buttons: ["This button text is way too long"]}

      assert {:error, [%{key: "buttons", message: message}]} =
               UtilityRewriter.rewrite(draft, user)

      assert message =~ "20 characters"
      assert Stub.calls() == []
    end

    test "rejects button text containing a variable without calling the model", %{user: user} do
      draft = %{@draft | buttons: ["Confirm {{1}}"]}

      assert {:error, [%{key: "buttons", message: _message}]} =
               UtilityRewriter.rewrite(draft, user)

      assert Stub.calls() == []
    end

    test "rejects button text containing emoji without calling the model", %{user: user} do
      draft = %{@draft | buttons: ["Confirm 👍"]}

      assert {:error, [%{key: "buttons", message: _message}]} =
               UtilityRewriter.rewrite(draft, user)

      assert Stub.calls() == []
    end
  end

  describe "rewrite/2 — draft validation" do
    test "rejects a blank body without calling the model", %{user: user} do
      draft = %{@draft | body: "   "}

      assert {:error, [%{key: "body", message: _message}]} = UtilityRewriter.rewrite(draft, user)
      assert Stub.calls() == []
    end
  end
end
