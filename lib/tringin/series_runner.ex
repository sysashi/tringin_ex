defmodule Tringin.SeriesRunner do
  use GenServer

  @moduledoc false

  @type state :: :ready | :running | :resting | :paused

  @type duration :: {:seconds, pos_integer()}

  @type t :: %__MODULE__{
          series: Tringin.Series.t(),
          state: state,
          start_delay: duration,
          rest_duration: duration,
          question_duration: duration,
          total_processed: non_neg_integer(),
          private: Map.t()
        }

  defstruct series: nil,
            state: :ready,
            start_delay: 3_000,
            rest_duration: 5_000,
            question_duration: 20_000,
            total_processed: 0,
            private: %{
              listeners: MapSet.new(),
              timers: %{},
              runtime_opts: %{}
            }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  # make sure series is provided
  def init(opts) do
    runtime_opts = Keyword.fetch!(opts, :runtime_opts)

    case Tringin.Runtime.register_series_process(runtime_opts, :series_runner) do
      {:ok, _} ->
        runner = struct(__MODULE__, Keyword.delete(opts, :private))
        runner = manage_private(runner, &Map.put(&1, :runtime_opts, runtime_opts))
        {:ok, runner}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def start_series(runner, config \\ []) do
    GenServer.call(runner, {:start_series, config})
  end

  def subscribe(runner) do
    GenServer.call(runner, :subscribe)
  end

  def unsubscribe(runner) do
    GenServer.call(runner, :unsubscribe)
  end

  def handle_call(:subscribe, {pid, _tag}, runner) do
    state_update = build_state_update(runner)

    runner =
      manage_private(runner, fn private ->
        %{private | listeners: MapSet.put(private.listeners, pid)}
      end)

    {:reply, {:ok, state_update}, runner}
  end

  def handle_call(:unsubscribe, {pid, _tag}, runner) do
    runner =
      manage_private(runner, fn private ->
        %{private | listeners: MapSet.delete(private.listeners, pid)}
      end)

    {:reply, :ok, runner}
  end

  def handle_call({:start_series, _config}, _from, runner) do
    state_update = build_state_update(runner)

    :ok = broadcast_state_update(runner, state_update)

    {:reply, {:ok, state_update}, set_timer(runner, :next_question)}
  end

  def handle_info(:next_question, runner) do
    case run_next_question(runner) do
      {:ok, _question, runner} ->
        :ok = broadcast_state_update(runner, build_state_update(runner))
        {:noreply, set_timer(runner, :rest)}

      {:error, reason} ->
        IO.warn("Runner: next question error: #{inspect(reason)}")
        {:noreply, runner}
    end
  end

  def handle_info(:rest, %{state: :running} = runner) do
    runner = %{runner | state: :resting}

    :ok = broadcast_state_update(runner, build_state_update(runner))

    {:noreply, set_timer(runner, :next_question)}
  end

  # Api
  alias __MODULE__

  @spec run_next_question(runner :: t()) ::
          {:ok, question :: any(), t()} | {:error, state} | {:error, any}
  def run_next_question(%SeriesRunner{state: state} = runner) when state in [:resting, :ready] do
    with {:ok, question, series} <- Tringin.Series.next_question(runner.series) do
      {:ok, question,
       %{runner | state: :running, series: series, total_processed: runner.total_processed + 1}}
    end
  end

  def run_next_question(%SeriesRunner{state: state}), do: {:error, state}

  # Utils

  def broadcast_state_update(
        %{private: %{runtime_opts: runtime_opts, listeners: listeners}},
        state_update
      ) do
    message = {:series_runner_update, state_update, {self(), make_ref()}}

    for pid <- listeners do
      Process.send(pid, message, [:nosuspend])
    end

    Tringin.Runtime.broadcast_message(
      runtime_opts,
      message
    )
  end

  def build_state_update(runner) do
    runner
    |> Map.from_struct()
    |> Map.put(:expected_duration, state_to_duration(runner))
    |> Map.put(:monotonic_ts, :erlang.monotonic_time())
    |> Map.delete(:private)
  end

  defp set_timer(%{private: %{timers: timers} = private} = runner, message) do
    timers =
      Map.put(
        timers,
        message,
        Process.send_after(self(), message, state_to_duration(runner))
      )

    %{runner | private: %{private | timers: timers}}
  end

  defp manage_private(%{private: private} = runner, fun) do
    %{runner | private: fun.(private)}
  end

  defp state_to_duration(%{state: :ready, start_delay: dur}), do: dur
  defp state_to_duration(%{state: :paused, start_delay: dur}), do: dur
  defp state_to_duration(%{state: :resting, rest_duration: dur}), do: dur
  defp state_to_duration(%{state: :running, question_duration: dur}), do: dur
end
