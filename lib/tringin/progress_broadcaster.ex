defmodule Tringin.ProgressBroadcaster do
  use GenServer

  alias Tringin.SeriesRegistry
  alias Tringin.SeriesRunner.Events.StateTransition
  alias Tringin.ProgressBroadcaster.Events.ProgressUpdate

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    series_registry = Keyword.fetch!(opts, :series_registry)

    state = %{
      rate: opts[:rate] || 250,
      series_registry: series_registry,
      latest_state_tag: {0, 0, 0},
      duration: 0,
      timer: nil
    }

    with {:ok, _} <-
           SeriesRegistry.register_series_process(series_registry, {:service, :progress_broadcaster}),
         {:ok, runner} <- SeriesRegistry.find_series_process(series_registry, :series_runner),
         {:ok, {runner, state_tag}} <- Tringin.SeriesRunnerExpirement.get_state(runner) do
      state =
        state
        |> Map.put(:duration, runner.expected_duration)
        |> Map.put(:latest_state_tag, state_tag)
        |> set_timer()

      {:ok, state}
    else
      error ->
        {:stop, error, state}
    end
  end

  def handle_info(%StateTransition{} = runner_update, state) do
    if state.timer do
      Process.cancel_timer(state.timer)
    end

    state =
      state
      |> Map.put(:duration, runner_update.expected_state_duration)
      |> Map.put(:latest_state_tag, runner_update.new_state_tag)
      |> set_timer()

    {:noreply, state}
  end

  def handle_info(:broadcast, %{latest_state_tag: {ts, _, _}} = state) do
    delta = :erlang.monotonic_time() - ts

    event = %ProgressUpdate{
      id: {self(), make_ref()},
      delta: delta,
      latest_state_tag: state.latest_state_tag
    }

    SeriesRegistry.broadcast(
      state.series_registry,
      [:listener],
      event
    )

    if :erlang.convert_time_unit(delta, :native, :millisecond) <= state.duration do
      {:noreply, set_timer(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    IO.warn("Progerss ignoring msg: #{inspect(msg)}")
    {:noreply, state}
  end

  defp set_timer(state) do
    %{state | timer: Process.send_after(self(), :broadcast, state.rate)}
  end
end
