defmodule Glific.CSV.Template do
  @moduledoc """
  Wrapper to allow each organization to modify how the templates are assembled. We will
  store this either in the DB and/or in the Flow CSV.

  For now, for experimental purposes we will store it in code :)
  """

  @doc """
  Given a template type and a language, returns the template to stich together the items from the CSV
  """
  @spec get_template(atom(), String.t()) :: String.t()
  def get_template(:content = _type, language) do
    case language do
      "hi" ->
        """
        आपने <%= menu_item %> का अनुरोध किया है। विषय पर अधिक जानकारी पढ़ने के लिए कृपया निम्न लिंक का उपयोग करें और फिर होमवर्क पूरा करें।
        <%= for {_, item} <- items do  %>
        <%= item %>
        <% end %>
        मुख्य मेनू पर वापस जाने के लिए 0 दबाएं।
        """

      # This is for english, but also serves as the default in case
      # we need it
      _ ->
        """
        You have requested <%= menu_item %>. Please use the following links to read more information on the topic and then complete the homework.
        <%= for {_, item} <- items do  %>
        <%= item %>
        <% end %>
        Press 0 to go back to the main menu.
        """
    end
  end

  def get_template(:menu = _type, _language) do
    """
    <%= for {item, index} <- items do  %>
      <%= index %>. <%= item %>
    <% end %>
    """
  end
end
