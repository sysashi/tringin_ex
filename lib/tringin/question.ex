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

  def prepare_answers(answers, correct_answer) do
    answers =
      answers
      |> Enum.shuffle()
      |> Enum.with_index()
      |> Enum.into(%{})

    %{
      answer: to_string(answers[correct_answer]),
      answers: format_answers(answers)
    }
  end

  def format_answers(answers) do
    for {answer, answer_id} <- answers, into: %{} do
      {to_string(answer_id), %{text: answer}}
    end
  end
end
