defmodule GlificWeb.Schema.Middleware.ChangesetErrors do
  @moduledoc """
  Implementing middleware functions to transform errors from Ecto Changeset into a format
  consumable and displayable to the API user. This version is specifically for mutations.
  """

  @behaviour Absinthe.Middleware

  @doc """
  This is the main middleware callback.

  It receives an %Absinthe.Resolution{} struct and it needs to return an %Absinthe.Resolution{} struct.
  The second argument will be whatever value was passed to the middleware call that setup the middleware.
  """
  @spec call(Absinthe.Resolution.t(), term()) :: Absinthe.Resolution.t()
  def call(res, _) do
    l = Map.get(res, :errors)

    if length(l) == 2 do
      [h | t] = l
      %{res | value: %{errors: [%{key: h, message: t}]}, errors: []}
    else
      with %{errors: [%Ecto.Changeset{} = changeset]} <- res do
        %{res | value: %{errors: transform_errors(changeset)}, errors: []}
      end
    end
  end

  @spec transform_errors(Ecto.Changeset.t()) :: Keyword.t()
  defp transform_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&format_error/1)
    |> Enum.map(fn
      {key, value} ->
        %{key: key, message: value}
    end)
  end

  @spec format_error(Ecto.Changeset.error()) :: String.t()
  defp format_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
