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
  node,0abf3b1c-5f79-48bf-9076-a72828d3bb39,We hope that helped you out.,Hindi We hope that helped you out. English
  node,85e897d2-49e4-42b7-8574-8dc2aee97121,Message for option 2. You can add them to a group based on their response.,Hindi Message for option 2. You can add them to a group based on their response. English
  node,a5105a7c-0917-4900-a0ce-cb5d3be2ffc5,Message for option 4,Hindi Message for option 4 English
  node,6d39df59-4572-4f4c-99b7-f667ea112e03,Message for option 3,Hindi Message for option 3 English
  node,f189f142-6d39-40fa-bf11-95578daeceea,Message for option 1,Hindi Message for option 1 English
  node,3ea030e9-41c4-4c6c-8880-68bc2828d67b,"Thank you for reaching out. This is your help message along with some options-
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
