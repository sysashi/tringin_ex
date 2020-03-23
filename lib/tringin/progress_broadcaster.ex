defmodule Tringin.ProgressBroadcaster do
  use GenServer

  alias Tringin.Runtime

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    runtime_opts = Keyword.fetch!(opts, :runtime_opts)

    state = %{
      rate: opts[:rate] || 250,
      runtime_opts: runtime_opts,
      latest_state_tag: {0, 0, 0},
      duration: 0,
      timer: nil
    }

    with {:ok, _} <-
           Runtime.register_series_process(runtime_opts, {:service, :progress_broadcaster}),
         {:ok, runner} <- Runtime.find_series_process(runtime_opts, :series_runner),
         {:ok, {runner, state_tag}} <- Tringin.SeriesRunner.get_state(runner) do
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

  def handle_info({:runner_update, {runner, state_tag}, _from}, state) do
    if state.timer do
      Process.cancel_timer(state.timer)
    end

    state =
      state
      |> Map.put(:duration, runner.expected_duration)
      |> Map.put(:latest_state_tag, state_tag)
      |> set_timer()

    {:noreply, state}
  end

  def handle_info(:broadcast, %{latest_state_tag: {ts, _, _}} = state) do
    delta = :erlang.monotonic_time() - ts

    Runtime.broadcast(
      state.runtime_opts,
      [:listener],
      {:progress_broadcaster, {delta, state.latest_state_tag}, {self(), make_ref()}}
    )

    if :erlang.convert_time_unit(delta, :native, :millisecond) <= state.duration do
      {:noreply, set_timer(state)}
    else
      {:noreply, state}
    end
  end

  defp set_timer(state) do
    %{state | timer: Process.send_after(self(), :broadcast, state.rate)}
  end
end
