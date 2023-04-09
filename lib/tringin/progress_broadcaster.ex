defmodule Tringin.ProgressBroadcaster do
  use GenServer

  alias Tringin.RunnerRegistry
  alias Tringin.Runner.Events.StateTransition
  alias Tringin.ProgressBroadcaster.Events.ProgressUpdate

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    {registry, opts} = Keyword.pop!(opts, :registry)
    config = Tringin.ProgressBroadcaster.Config.new!(opts) |> Map.new()

    state = %{
      rate: config.rate,
      registry: registry,
      latest_state_tag: {0, 0, 0},
      duration: 0,
      timer: nil
    }

    with {:ok, _} <-
           RunnerRegistry.register_runner_process(registry, {:service, :progress_broadcaster}),
         {:ok, runner} <- RunnerRegistry.find_runner_process(registry, :runner),
         {:ok, {runner, state_tag}} <- Tringin.Runner.get_state(runner) do
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

    RunnerRegistry.broadcast(
      state.registry,
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
