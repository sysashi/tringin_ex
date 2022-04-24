defmodule Tringin.SeriesRunnerExpirement do
  @moduledoc """
  ## States

    * `:waiting`
    * `:running`
    * `:resting`
    * `:paused`

  ## Events

  `:start` start series if its not started
  `:stop` restarts the series if its possible

  `:pause` pauses at the next rest duration
  `:force_pause` pauses running state at current duration

  `:continue` runs series again if previous state was paused
  `:restart_last` restarts last question if state was in :running or :force_paused

  ## Delays and Durations

    * `:start_delay` delay before `:waiting` is changed to `:running`
    * `:run_duration` duration of `:running` state
    * `:rest_duration` delay before `:resting` is changed to `:running`
    * `:post_pause_delay` delay before `:paused` transitioned to `:running`

  ## Automatic Mode

  Requires states timeouts to be set

  ## Manual Mode

  State Transitions will not happen automatically based on duration and delays. Runner will
  accept additional set of events in order to progerss through series.

    * `:move` moves series to next question (relative to current position)
    * `{:move, n}` moves series to Nth question (relative to current position)
    * `{:set, n}` moves series to Nth question

  First approach would be to use generic timeouts and keep track of them,
  so we would know how much left for the specific state to run and can
  continue from that state for remaining timer

  Second approach would be to skip need for keeping track of timeouts and
  restart previous :waiting state
  """

  @behaviour :gen_statem

  require Logger

  alias Tringin.SeriesRunner.Events.{
    ConfigChanged,
    Initialized,
    StateTransition
  }

  alias Tringin.SeriesRegistry

  def child_spec(init_arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [init_arg]}
    }
  end

  defstruct series: nil,
            run_mode: :automatic,
            start_delay: 3000,
            run_duration: 20_000,
            rest_duration: 5000,
            post_pause_delay: 3000,
            state: nil,
            series_registry: nil,
            private: %{
              state_tag: {0, 0, 0},
            }

  def start_series(runner_pid, config \\ []) do
    :gen_statem.call(runner_pid, {:start_series, config})
  end

  def get_state(runner_pid) do
    :gen_statem.call(runner_pid, :get_state)
  end

  @doc false
  def start_link(opts) do
    :gen_statem.start_link(__MODULE__, opts, [])
  end

  @impl true
  def init(opts) do
    registry = Keyword.fetch!(opts, :series_registry)

    case SeriesRegistry.register_series_process(registry, :series_runner) do
      {:ok, _} ->
        runner =
          struct(__MODULE__, Keyword.delete(opts, :private))
          |> put_private(:state_tag, gen_state_tag())

        {:ok, :waiting, runner}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def callback_mode(), do: [:handle_event_function, :state_enter]

  @impl true
  def handle_event({:call, from}, :state, state, _runner) do
    {:keep_state_and_data, {:reply, from, state}}
  end

  def handle_event({:call, from}, :get_state, _state, runner) do
    {:keep_state_and_data, {:reply, from, {:ok, build_state_snapshot(runner)}}}
  end

  def handle_event(:enter, old_state, new_state, runner) do
    Logger.debug(
      "Tringin.SeriesRunner transition from: #{inspect(old_state)} to: #{inspect(new_state)}"
    )

    new_state_tag = gen_state_tag()
    old_state_tag = runner.private.state_tag

    runner =
      runner
      |> Map.put(:state, new_state)
      |> put_private(:state_tag, new_state_tag)

    {:keep_state, broadcast_state_transition(runner, old_state, old_state_tag, new_state)}
  end

  def handle_event(:cast, {:move, _n}, :running, _runner) do
    :keep_state_and_data
  end

  def handle_event(:cast, {:move, _}, _state, _runner) do
    :keep_state_and_data
  end

  def handle_event(:cast, :pause, state, runner) when state in [:running, :resting] do
    {:next_state, :paused, runner}
  end

  def handle_event(:cast, :pause, _state, _runner) do
    :keep_state_and_data
  end

  def handle_event(:cast, :continue, :paused, _runner) do
    :keep_state_and_data
  end

  # Starting series

  def handle_event({:call, from}, {:start_series, _}, :waiting, runner) do
    {
      :keep_state_and_data,
      [
        {:state_timeout, runner.start_delay, :run},
        {:reply, from, {:ok, build_state_snapshot(runner)}}
      ]
    }
  end

  ## Ignore start_series calls if state is not "waiting"

  def handle_event(:cast, :start_series, _, _) do
    :keep_state_and_data
  end

  # Run series

  def handle_event(:state_timeout, :run, state, runner)
      when state in [:waiting, :start_delay, :resting] do
    with {:ok, series} <- Tringin.Series.next_question(runner.series) do
      runner = %{runner | state: :running, series: series}

      case runner.run_mode do
        :manual ->
          {:next_state, :running, runner}

        :automatic ->
          {:next_state, :running, runner, {:state_timeout, runner.run_duration, :rest}}
      end
    else
      _ -> :keep_state_and_data
    end
  end

  def handle_event(:state_timeout, :rest, :running, runner) do
    {:next_state, :resting, runner, {:state_timeout, runner.rest_duration, :run}}
  end

  def gen_state_tag(),
    do: {
      :erlang.monotonic_time(),
      :erlang.unique_integer([:monotonic]),
      :erlang.time_offset()
    }

  def broadcast_state_transition(runner, old_state, old_state_tag, new_state) do
    event = %StateTransition{
      id: {self(), make_ref()},
      previous_state: old_state,
      previous_state_tag: old_state_tag,
      new_state: new_state,
      new_state_tag: runner.private.state_tag,
      expected_state_duration: state_to_duration(runner)
    }

    SeriesRegistry.broadcast(
      runner.series_registry,
      [:service, :listener],
      event
    )

    runner
  end

  def build_state_snapshot(runner) do
    data =
      runner
      |> Map.from_struct()
      |> Map.put(:expected_duration, state_to_duration(runner))
      |> Map.delete(:private)

    {data, runner.private.state_tag}
  end

  defp put_private(%{private: private} = runner, key, value) do
    %{runner | private: Map.put(private, key, value)}
  end

  defp state_to_duration(%{state: :waiting, start_delay: dur}), do: dur
  defp state_to_duration(%{state: :running, run_duration: dur}), do: dur
  defp state_to_duration(%{state: :resting, rest_duration: dur}), do: dur
  defp state_to_duration(%{state: :paused, post_pause_delay: dur}), do: dur

  defp state_to_duration(%{state: state}) do
    Logger.warn("Tringin.SeriesRunner unknown duration for #{inspect(state)} state")
    nil
  end
end
