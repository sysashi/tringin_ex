defmodule Tringin.Source do
  @moduledoc false

  defstruct [:id]

  @type t :: %__MODULE__{}

  def next_question(%source_mod{} = source, params \\ []) do
    source_mod.next_question(source, params)
  end

  def next_question(_source, _opts) do
    {:ok,
     %{
       text: "2 + 2?",
       answers: [:a, :b, :c, :d],
       answer: :b
     }}
  end
end
