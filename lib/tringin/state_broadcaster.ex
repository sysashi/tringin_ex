defmodule Tringin.StateBroadcaster do
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
      latest_state_snapshot: nil
    }

    with {:ok, _} <-
           Runtime.register_series_process(runtime_opts, {:service, :state_broadcaster}),
         {:ok, runner} <- Runtime.find_series_process(runtime_opts, :series_runner),
         {:ok, state_snapshot} <- Tringin.SeriesRunner.get_state(runner) do
      {:ok, %{state | latest_state_snapshot: state_snapshot}, {:continue, :setup}}
    else
      error ->
        {:stop, error, state}
    end
  end

  def handle_continue(:setup, state) do
    set_timer(state.rate)
    {:noreply, state}
  end

  def handle_info({:runner_update, state_snapshot, _from}, state) do
    {:noreply, %{state | latest_state_snapshot: state_snapshot}}
  end

  def handle_info(:broadcast, %{latest_state_snapshot: {runner_state, state_tag}} = state) do
    {event_ts, _, _} = state_tag
    delta = :erlang.monotonic_time() - event_ts
    runner_state = Map.put(runner_state, :progress_delta, delta)

    Runtime.broadcast(
      state.runtime_opts,
      [:listener],
      {:state_broadcaster, {runner_state, state_tag}, {self(), make_ref()}}
    )

    set_timer(state.rate)

    {:noreply, state}
  end

  defp set_timer(rate) do
    Process.send_after(self(), :broadcast, rate)
  end
end
