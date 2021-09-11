defmodule Tringin.SeriesRunnerExpirement do
  @moduledoc false

  def child_spec(init_arg) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [init_arg]}}
  end

  defstruct series: nil,
            run_mode: :automatic,
            start_delay: 3000,
            run_duration: 20_000,
            rest_duration: 5000,
            post_pause_delay: 3000,
            state: nil,
            private: %{
              state_tag: {0, 0, 0},
              runtime_opts: %{}
            }

  @behaviour :gen_statem
  # states = [:waiting, :running, :resting, :paused]
  #
  # events = [:start, :stop, :pause, :continue]
  # :stop restarts the series
  #
  # options:
  #   * run_mode -
  #     * manual - states are not changed based on timeouts, requires explicitly to
  #       send "move" event, :running state still can have a timeout.
  #     * automatic - requires states timouts to be set.
  #   * start_delay - delay before :waiting is changed to :running
  #   * run_duration
  #   * rest_duration (ignored when run_type is manual)
  #   * post_pause_delay - delay before :paused transitioned to :running

  # Pause
  # When state is :running or :resting :pause event can be handled.
  #
  # First approach would be to use generic timeouts and keep track of them,
  # so we would know how much left for the specific state to run and can
  # continue from that state for remaining timer
  #
  # Second approach would be to skip need for keeping track of timeouts and
  # restart previous :waiting state

  def start_link(opts) do
    :gen_statem.start_link(__MODULE__, opts, [])
  end

  @impl true
  def init(opts) do
    runtime_opts = Keyword.fetch!(opts, :runtime_opts)

    case Runtime.register_series_process(runtime_opts, :series_runner) do
      {:ok, _} ->
        runner =
          struct(__MODULE__, Keyword.delete(opts, :private))
          |> put_private(:runtime_opts, runtime_opts)
          |> put_private(:state_tag, gen_state_tag())

        {:ok, :waiting, runner}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  # def init(opts) do
  #   runner =
  #     struct(__MODULE__, Keyword.delete(opts, :private))

  #   {:ok, :waiting, runner}
  # end
  #

  def start_series(runner_pid, config \\ []) do
    :gen_statem.call(runner_pid, {:start_series, config})
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

  def handle_event(:enter, _old_state, new_state, runner) do
    IO.puts("Transition to: #{new_state}")
    new_state_tag = gen_state_tag()

    # if runner.private.state_tag >= new_state_tag do
    #   raise "Previous state tag is greater or eq!:" <>
    #           " #{inspect(runner.private.state_tag)} >= #{inspect(new_state_tag)}"
    # end

    runner = put_private(runner, :state_tag, new_state_tag)
    runner = %{runner | state: new_state}

    broadcast_state_transition(runner)

    {:keep_state, runner}
  end

  def handle_event(:cast, {:move, n}, :running, runner) do
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

  def handle_event(:cast, :continue, :paused, runner) do
    :keep_state_and_data
  end

  # Starting series

  def handle_event(:cast, :start_series, :waiting, runner) do
    IO.puts("Starting series...")
    {:next_state, :start_delay, runner, {:state_timeout, runner.start_delay, :run}}
  end

  def handle_event({:call, from}, {:start_series, _}, :waiting, runner) do
    runner_snapshot = build_state_snapshot(runner)

    {:next_state, :start_delay, runner,
     [{:state_timeout, runner.start_delay, :run}, {:reply, from, {:ok, runner_snapshot}}]}
  end

  ## Ignore start_series calls if state is not "waiting"

  def handle_event(:cast, :start_series, _, _) do
    :keep_state_and_data
  end

  # Run series

  def handle_event(:state_timeout, :run, state, runner) when state in [:start_delay, :resting] do
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

  def broadcast_state_transition(runner) do
    transition_message =
      {
        :runner_update,
        build_state_snapshot(runner),
        {self(), make_ref()}
      }

    Tringin.Runtime.broadcast(
      runner.private.runtime_opts,
      [:service, :listener],
      transition_message
    )

    :ok
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
    IO.warn("Unknown state: #{state}")
    nil
  end
end
