defmodule Tringin.Source do
  @type context :: Map.t()
  @callback next_question(context, params :: keyword) ::
              {:ok, Tringin.Question.t()} | {:error, any()}
end
