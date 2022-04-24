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

  ###

  alias Tringin.Runtime

  def start_supervised(registry, name, config) do
    unless config[:runner][:series] do
      raise ArgumentError,
            "runner requires series to be set, found none in config #{inspect(config[:runner])}"
    end

    registered_processes = Runtime.list_series_processes(registry, name)

    unless Enum.empty?(registered_processes) do
      msg =
        registered_processes
        |> Enum.map(fn {role, pid} -> "#{inspect role}: #{inspect pid}" end)
        |> Enum.join("\n")

      raise "series is already in registry, found following processes\n#{msg}"
    end
  end
end
