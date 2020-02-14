defmodule Tringin.Question do
  @moduledoc false

  @type answer :: any

  @type choice :: :a | :b | :c | :d

  @type question :: binary

  @type t :: %{
          question: question,
          possible_answers: [answer],
          check_answer: (choice -> :correct | :wrong)
        }
end
