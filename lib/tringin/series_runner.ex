defmodule Tringin.SeriesRunner do
  use GenServer

  @moduledoc false

  @type state :: :ready | :running | :resting | :paused

  @type duration :: non_neg_integer()

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
              timer: :unset,
              state_tag: {0, 0, 0},
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
        runner =
          __MODULE__
          |> struct(Keyword.delete(opts, :private))
          |> put_private(:runtime_opts, runtime_opts)
          |> put_private(:state_tag, gen_state_tag())

        {:ok, runner}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def get_state(runner) do
    GenServer.call(runner, :get_state)
  end

  def start_series(runner, config \\ []) do
    GenServer.call(runner, {:start_series, config})
  end

  def handle_call(:get_state, _from, runner) do
    {:reply, {:ok, build_state_snapshot(runner)}, runner}
  end

  # TODO: don't attempt to start running series
  def handle_call({:start_series, _config}, _from, runner) do
    {:reply, {:ok, build_state_snapshot(runner)}, transition_to(runner, :running)}
  end

  def handle_info({:set, :running}, runner) do
    case move_series(runner) do
      {:ok, runner} ->
        {:noreply, transition_to(runner, :resting)}

      {:error, reason} ->
        IO.warn("Runner: next question error: #{inspect(reason)}")

        {:noreply, runner}
    end
  end

  def handle_info({:set, :resting}, runner) do
    case rest(runner) do
      {:ok, runner} ->
        {:noreply, transition_to(runner, :running)}

      {:error, reason} ->
        IO.warn("Runner:rest error: #{inspect(reason)}")

        {:noreply, runner}
    end
  end

  # Api
  alias __MODULE__

  @spec move_series(t()) :: {:ok, t()} | {:error, state} | {:error, any}
  def move_series(%SeriesRunner{state: state} = runner) when state in [:resting, :ready] do
    with {:ok, series} <- Tringin.Series.next_question(runner.series) do
      {:ok,
       %{runner | state: :running, series: series, total_processed: runner.total_processed + 1}}
    end
  end

  def move_series(%SeriesRunner{state: state}), do: {:error, state}

  def rest(%SeriesRunner{state: :running} = runner) do
    {:ok, %{runner | state: :resting}}
  end

  def rest(%SeriesRunner{state: state}), do: {:error, state}

  # Utils

  def transition_to(runner, new_state) do
    new_state_tag = gen_state_tag()

    if runner.private.state_tag >= new_state_tag do
      raise "Previous state tag is greater or eq!:" <>
              " #{inspect(runner.private.state_tag)} >= #{inspect(new_state_tag)}"
    end

    duration = state_to_duration(runner)

    runner
    |> put_private(:state_tag, new_state_tag)
    |> broadcast_state_transition()
    |> set_timer(duration, {:set, new_state})
  end

  def broadcast_state_transition(%SeriesRunner{} = runner) do
    transition_message = {
      :runner_update,
      build_state_snapshot(runner),
      {self(), make_ref()}
    }

    Tringin.Runtime.broadcast(
      runner.private.runtime_opts,
      [:service, :listener],
      transition_message
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

  defp set_timer(%{private: %{timer: :unset}} = runner, duration, message) do
    put_private(
      runner,
      :timer,
      Process.send_after(self(), message, duration)
    )
  end

  defp set_timer(%{private: %{timer: timer}} = runner, dur, msg) when is_reference(timer) do
    if left = Process.read_timer(timer) do
      IO.warn(
        "Overwriting current timer (left: #{left}, state: #{inspect(runner.state)})" <>
          " with message: #{inspect(msg)} (duration: #{dur})."
      )

      Process.cancel_timer(timer)
    end

    runner
    |> put_private(:timer, :unset)
    |> set_timer(dur, msg)
  end

  defp put_private(%{private: private} = runner, key, value) do
    %{runner | private: Map.put(private, key, value)}
  end

  defp state_to_duration(%{state: :ready, start_delay: dur}), do: dur
  defp state_to_duration(%{state: :paused, start_delay: dur}), do: dur
  defp state_to_duration(%{state: :resting, rest_duration: dur}), do: dur
  defp state_to_duration(%{state: :running, question_duration: dur}), do: dur

  def gen_state_tag(),
    do: {
      :erlang.monotonic_time(),
      :erlang.unique_integer([:monotonic]),
      :erlang.time_offset()
    }
end
