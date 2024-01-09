defmodule GlificWeb.Schema.FlowL10NTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase

  alias Glific.{
    Seeds.SeedsDev
  }

  setup do
    SeedsDev.seed_test_flows()
    :ok
  end

  load_gql(:export_l10n, GlificWeb.Schema, "assets/gql/flows/export_l10n.gql")
  load_gql(:import_l10n, GlificWeb.Schema, "assets/gql/flows/import_l10n.gql")
  load_gql(:inline_l10n, GlificWeb.Schema, "assets/gql/flows/inline_l10n.gql")

  @help_export """
  Type,UUID,en,hi
  Type,UUID,English,Hindi
  action,4cbb069d-99b0-4493-826a-13558107e366,We hope that helped you out.,Hindi We hope that helped you out. English
  action,a970d5d9-2951-48dc-8c66-ee6833c4b21e,Message for option 2. You can add them to a group based on their response.,Hindi Message for option 2. You can add them to a group based on their response. English
  action,36051723-7d00-422e-8846-2336a9ecbc9d,Message for option 4,Hindi Message for option 4 English
  action,10196f43-87f0-4205-aabd-1549aaa7e242,Message for option 3,Hindi Message for option 3 English
  action,ed7d10f7-6298-4d84-a8d2-7b1f6e91da07,Message for option 1,Hindi Message for option 1 English
  action,e319cd39-f764-4680-9199-4cb7da647166,"Thank you for reaching out. This is your help message along with some options-
  \ \ \ \ \ \ \

  *Type 1* for option 1
  *Type 2* for option 2
  *Type 3* for option 3
  *Type 4* to optout and stop receiving our messages","बाहर तक पहुँचने के लिए धन्यवाद। क्या यह आप के लिए देख रहे हैं- टाइप 1, ग्लिफ़ टाइप 2 के बारे में अधिक जानने के लिए, यदि आप ग्लिफ़ टाइप 3 के लिए शानदार वेबसीइट टाइप 4 से आउटपुट के लिए ऑनबोर्ड होना चाहते हैं"
  """

  test "flows export return a string with csv", %{manager: user} do
    result = auth_query_gql_by(:export_l10n, user, variables: %{"id" => 1})
    assert {:ok, query_data} = result

    data = get_in(query_data, [:data, "exportFlowLocalization", "export_data"])
    assert data == @help_export
  end

  test "flows import returns success", %{manager: user} do
    result =
      auth_query_gql_by(:import_l10n, user,
        variables: %{"localization" => @help_export, "id" => 1}
      )

    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "importFlowLocalization", "success"]) == true
  end

  test "flows translate returns success", %{manager: user} do
    result = auth_query_gql_by(:inline_l10n, user, variables: %{"id" => 1})
    assert {:ok, query_data} = result
    assert get_in(query_data, [:data, "inlineFlowLocalization", "success"]) == true
  end
end
