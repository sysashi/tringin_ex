defmodule Tringin.Series do
  @moduledoc false

  alias Tringin.{Series, Source}

  @type t :: %__MODULE__{
          source: Source.t(),
          position: pos_integer(),
          current_question: any()
        }

  defstruct [:source, :position, :current_question]

  @spec init_series(source :: Source.t(), params :: keyword()) :: {:ok, t()} | {:error, any()}
  def init_series(source, params \\ []) do
    params =
      params
      |> Map.new()
      |> Map.put_new(:position, 1)

    with {:ok, question} <- Source.next_question(source, offset: params.position) do
      params =
        params
        |> Map.put(:source, source)
        |> Map.put(:current_question, question)

      {:ok, struct(__MODULE__, params)}
    end
  end

  def next_question(%Series{source: source, position: pos} = series) do
    with {:ok, question} <- Source.next_question(source, offset: pos) do
      {:ok, question, %{series | current_question: question, position: pos + 1}}
    end
  end
end
