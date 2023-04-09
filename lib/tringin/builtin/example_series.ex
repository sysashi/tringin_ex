# defmodule Tringin.Builtin.ExampleSeries do
#   @moduledoc false
#
#   defstruct current_question: nil, current_position: 0
#
#   alias __MODULE__
#
#   def new() do
#     %__MODULE__{
#       current_question: question(1),
#       current_position: 1
#     }
#   end
#
#   defimpl Tringin.SeriesProto do
#     def id(_series), do: "tringin.example_series"
#
#     def length(_series), do: 999
#
#     def initialize(_series) do
#       {:ok, %ExampleSeries{}}
#     end
#
#     def restart(_series) do
#       {:ok, %ExampleSeries{
#         current_question: ExampleSeries.question(1),
#         current_position: 1
#       }}
#     end
#
#     def load_question(_series, n) do
#       {:ok,
#        %ExampleSeries{
#          current_question: ExampleSeries.question(n),
#          current_position: n
#        }}
#     end
#
#     def load_next_question(series) do
#       {:ok,
#        %ExampleSeries{
#          current_question: ExampleSeries.question(series.current_position + 1),
#          current_position: series.current_position + 1
#        }}
#     end
#
#     def get_current_question(series) do
#       {:ok, series.current_question}
#     end
#
#     def get_current_position(series) do
#       series.current_position
#     end
#   end
#
#   alias Tringin.Series
#
#   def init(_opts) do
#     %Series{
#       current_question: question(1),
#       handler: __MODULE__,
#       position: 1
#     }
#   end
#
#   def move(series, n) do
#     IO.inspect({series, n})
#
#     {:ok,
#      %{series | current_question: question(series.position + n), position: series.position + n}}
#   end
#
#   def pause(series) do
#     series
#   end
#
#   def stop(series) do
#     series
#   end
#
#   def question(n) do
#     text = "Example question #{n}"
#     answer = "Correct Answer"
#     incorrect_answers = Enum.map(1..3, &"Incorrect Answer #{&1}")
#
#     answers = Tringin.Question.prepare_answers([answer | incorrect_answers], answer)
#
#     Map.put(answers, :text, text)
#   end
# end
