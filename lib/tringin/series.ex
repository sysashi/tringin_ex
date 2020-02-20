defmodule Tringin.Series do
  @moduledoc false

  alias Tringin.Series

  @type t :: %__MODULE__{
          source: atom(),
          source_context: Map.t(),
          position: pos_integer(),
          current_question: any()
        }

  defstruct source: nil,
            source_context: %{},
            position: 1,
            current_question: nil

  @spec next_question(t(), extra_params :: Map.t()) :: {:ok, t()} | {:error, any()}
  def next_question(%Series{source: source, source_context: ctx} = series, extra \\ %{}) do
    with {:ok, question} <- source.next_question(ctx, Map.put(extra, :position, series.position)) do
      {:ok, %{series | current_question: question, position: series.position + 1}}
    end
  end
end
