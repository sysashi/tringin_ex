defmodule Tringin.Runner do
  @moduledoc """
  ## States

    * `:waiting`
    * `:running`
    * `:resting`
    * `:paused`
    * `:ended`

  ## Events

  `:start` start runner if its not started
  `:stop` restarts the runner if its possible

  `:pause` pauses at the next rest duration
  `:force_pause` pauses running state at current duration (not implemented)

  `:continue` runs runner again if previous state was paused
  `:restart_last` restarts last question if state was in :running or :force_paused (rename?)

  `:reset` ? instead of restarts

  ## Delays and Durations

    * `:start_delay` delay before `:waiting` is changed to `:running`
    * `:run_duration` duration of `:running` state
    * `:rest_duration` delay before `:resting` is changed to `:running`
    * `:post_pause_delay` delay before `:paused` transitioned to `:running`

  ## Automatic Mode

  Requires states timeouts to be set

  ## Manual Mode

  State Transitions will not happen automatically based on duration and delays. Runner will
  accept additional set of events in order to progerss through runner

    * `:move` moves runner to next question (relative to current position)
    * `{:move, n}` moves runner to Nth question (relative to current position)
    * `{:set, n}` moves runner to Nth question

  First approach would be to use generic timeouts and keep track of them,
  so we would know how much left for the specific state to run and can
  continue from that state for remaining timer

  Second approach would be to skip need for keeping track of timeouts and
  restart previous :waiting state
  """

  # :initialized
  # :waiting (starting), waiting for a command
  # :running
  # :resting
  # :paused (next state: resting | running)
  # :ended

  # waiting <- start (unless start_delay not set)
  # ended <- restart, move
  # running <- pause, force_pause, stop, restart, end
  # paused <- continue, stop, restart, end
  # resting <- pause, force_pause, stop, restart, end

  @behaviour :gen_statem

  @registry Application.compile_env(:tringin_ex, :registry, Tringin.LocalRegistry)

  require Logger

  alias Tringin.Runner.Config

  alias Tringin.Runner.Events.{
    ConfigChanged,
    Initialized,
    StateTransition
  }

  def child_spec(init_arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [init_arg]}
    }
  end

  defstruct run_mode: :automatic,
            start_delay: 3000,
            run_duration: 20_000,
            rest_duration: 5000,
            post_pause_delay: 0,
            state: nil,
            position: 1,
            direction: :forward,
            registry: nil,
            private: %{
              state_tag: {0, 0, 0}
            }

  ## Controls

  def start(runner) do
    :gen_statem.call(runner, :start)
  end

  def stop(runner, reason) when is_atom(reason) do
    :gen_statem.call(runner, {:stop, reason})
  end

  # FIXME
  def restart(runner) do
    :gen_statem.cast(runner, :restart)
  end

  def pause(runner) do
    :gen_statem.cast(runner, :pause)
  end

  def continue(runner) do
    :gen_statem.cast(runner, :continue)
  end

  def next(runner) do
    :gen_statem.call(runner, :next)
  end

  def set(runner, n) do
    :gen_statem.call(runner, {:set, n})
  end

  ## Util

  def configure(runner, config) do
    :gen_statem.call(runner, {:configure, config})
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
    {registry, opts} = Keyword.pop!(opts, :registry)
    config = Config.new!(opts) |> Map.new()

    case @registry.register_process(registry, :runner) do
      {:ok, _} ->
        runner =
          struct(__MODULE__, config)
          |> Map.put(:registry, registry)
          |> Map.put(:position, config.starting_position)
          |> put_private(:state_tag, gen_state_tag())

        broadcast_init(runner)

        {:ok, :waiting, runner}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def callback_mode(), do: [:handle_event_function, :state_enter]

  @impl true
  def handle_event(:enter, old_state, new_state, runner) do
    Logger.debug(
      "Tringin.Runner transition from: #{inspect(old_state)} to: #{inspect(new_state)}"
    )

    new_state_tag = gen_state_tag()
    old_state_tag = runner.private.state_tag

    runner =
      runner
      |> Map.put(:state, new_state)
      |> put_private(:state_tag, new_state_tag)

    {:keep_state, broadcast_state_transition(runner, old_state, old_state_tag, new_state)}
  end

  def handle_event({:call, from}, :get_state, _state, runner) do
    {:keep_state_and_data, {:reply, from, {:ok, build_state_snapshot(runner)}}}
  end

  def handle_event({:call, from}, {:configure, config}, _state, runner) do
    case update_config(runner, config) do
      {:ok, updated_runner} ->
        old_config = extract_config(runner)
        broadcast_config_change(updated_runner, old_config)

        {:keep_state, updated_runner, {:reply, from, :ok}}

      {:error, reason} ->
        {:keep_state, runner, {:reply, from, {:error, reason}}}
    end
  end

  ## Starting Runner

  def handle_event({:call, from}, :start, :waiting, %{run_mode: :automatic} = runner) do
    next_event =
      if runner.start_delay && runner.start_delay >= 0 do
        {:starting, start_timer(runner, :starting)}
      else
        {:running, start_timer(runner, :running)}
      end

    {
      :next_state,
      next_event,
      runner,
      {:reply, from, {:ok, build_state_snapshot(runner)}}
    }
  end

  def handle_event({:call, from}, :start, :waiting, %{run_mode: :manual} = runner) do
    {
      :next_state,
      {:running, :manual, runner.position},
      runner,
      {:reply, from, {:ok, build_state_snapshot(runner)}}
    }
  end

  def handle_event(:info, {:timeout, tref, _}, {:starting, tref}, runner) do
    {
      :next_state,
      {:running, start_timer(runner, :running)},
      runner
    }
  end

  def handle_event({:call, from}, :start, {:paused, _}, _runner) do
    {:keep_state_and_data, [{:reply, from, :ok}, {:next_event, :internal, :continue}]}
  end

  def handle_event({:call, from}, :start, {:stopped, reason}, _runner) do
    {:keep_state_and_data, {:reply, from, {:error, {:stopped, reason}}}}
  end

  def handle_event({:call, from}, :start, _, _runner) do
    {:keep_state_and_data, {:reply, from, {:error, :already_running}}}
  end

  ## Stopping

  def handle_event({:call, from}, {:stop, reason}, state, runner) do
    # handle states with timeouts
    case state do
      {:unpausing, {tref, _}} ->
        :erlang.cancel_timer(tref)

      {_state, tref} when is_reference(tref) ->
        :erlang.cancel_timer(tref)

      _ ->
        :ok
    end

    {:next_state, {:stopped, reason}, runner, {:reply, from, :ok}}
  end

  ## Restart

  def handle_event(:cast, :restart, {:paused, _paused_state}, _runner) do
    :keep_state_and_data
  end

  def handle_event(:cast, :restart, {:unpausing, {_tref, _paused_state}}, _runner) do
    :keep_state_and_data
  end

  def handle_event(:cast, :restart, state, runner) do
    Logger.debug("Restarting #{inspect(state)}")

    case state do
      {_state, tref} when is_reference(tref) ->
        :erlang.cancel_timer(tref)

      _ ->
        :ok
    end

    {:next_state, :waiting, set_position(runner, 1)}
  end

  ## Pause

  def handle_event(:cast, :pause, {state, tref}, runner)
      when state in [:starting, :running, :resting] do
    case :erlang.cancel_timer(tref) do
      remaining_ms when is_integer(remaining_ms) ->
        {:next_state, {:paused, {state, remaining_ms}}, runner}

      other ->
        raise "Could not cancel timer at state: #{state}, got: #{other}"
        {:next_state, {:paused, state}, runner}
    end
  end

  def handle_event(:cast, :pause, _state, _runner) do
    :keep_state_and_data
  end

  ## Continue/Unpause

  # unpausing state is more complex than the others
  # {:unpausing, unpausing_tref, paused_state}
  def handle_event(_event_type, :continue, {:paused, {state, remaining_ms}}, runner) do
    next_event =
      if runner.post_pause_delay && runner.post_pause_delay >= 0 do
        {:unpausing, {start_timer(runner, :unpausing), {state, remaining_ms}}}
      else
        {state, start_timer(remaining_ms, state)}
      end

    {:next_state, next_event, runner}
  end

  def handle_event(:info, {:timeout, tref, _}, {:unpausing, {tref, paused}}, runner) do
    {state, remaining_ms} = paused
    {:next_state, {state, start_timer(remaining_ms, state)}, runner}
  end

  def handle_event(_event_type, :continue, _state, _runner) do
    :keep_state_and_data
  end

  ## Manual run

  def handle_event({:call, from}, :next, {:running, :manual, _}, runner) do
    runner = set_next_position(runner)

    {
      :next_state,
      {:running, :manual, runner.position},
      runner,
      {:reply, from, :ok}
    }
  end

  def handle_event({:call, from}, :next, _state, _runner) do
    {:keep_state_and_data, {:reply, from, {:error, :invalid_state}}}
  end

  ## Automatic run

  def handle_event(:info, {:timeout, tref, _}, {:running, tref}, runner) do
    {next_event, runner} =
      if runner.rest_duration && runner.rest_duration >= 0 do
        {{:resting, start_timer(runner, :resting)}, runner}
      else
        {{:running, start_timer(runner, :running)}, set_next_position(runner)}
      end

    {
      :next_state,
      next_event,
      runner
    }
  end

  def handle_event(:info, {:timeout, tref, _}, {:resting, tref}, runner) do
    {
      :next_state,
      {:running, start_timer(runner, :running)},
      set_next_position(runner)
    }
  end

  ## Lost timeouts

  # Runner was restarted, some timers could still be running and finishing
  # should we keep track of all timers and cancel them on restart?
  # def handle_event(:info, {:timeout, _tref, _}, :waiting, _runner) do
  #   :keep_state_and_data
  # end

  def handle_event(:info, {:timeout, _tref, timedout_state}, state, _runner) do
    Logger.error(
      "Wild timeout appears at state: #{inspect(state)}, timedout_state: #{inspect(timedout_state)}"
    )

    :keep_state_and_data
  end

  # integer duration is used for starting "remaining" duration
  # of a state from pause
  defp start_timer(duration, next_state) when is_integer(duration) do
    :erlang.start_timer(
      duration,
      self(),
      next_state
    )
  end

  defp start_timer(runner, next_state) do
    :erlang.start_timer(
      timer_dur(runner, next_state),
      self(),
      next_state
    )
  end

  def timer_dur(%{start_delay: dur}, :starting), do: dur
  def timer_dur(%{run_duration: dur}, :running), do: dur
  def timer_dur(%{rest_duration: dur}, :resting), do: dur
  def timer_dur(%{post_pause_delay: dur}, :unpausing), do: dur

  ## Util

  def update_config(runner, config) do
    with {:ok, config} <- Config.new(config) do
      {:ok, struct(runner, config)}
    end
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
      previous_state: simple_state(old_state),
      previous_state_tag: old_state_tag,
      new_state: simple_state(new_state),
      new_state_tag: runner.private.state_tag,
      expected_state_duration: state_to_duration(runner, old_state),
      current_position: runner.position
    }

    @registry.broadcast(
      runner.registry,
      [:service, :listener],
      event
    )

    runner
  end

  def broadcast_init(runner) do
    event = %Initialized{
      config:
        Map.take(runner, [
          :run_mode,
          :start_delay,
          :run_duration,
          :rest_duration,
          :post_pause_delay,
          :state,
          :position,
          :direction
        ])
    }

    @registry.broadcast(
      runner.registry,
      [:service, :listener],
      event
    )

    runner
  end

  def broadcast_config_change(runner, old_config) do
    event = %ConfigChanged{
      id: {self(), make_ref()},
      old_config: old_config,
      new_config: extract_config(runner)
    }

    @registry.broadcast(
      runner.registry,
      [:service, :listener],
      event
    )

    runner
  end

  defp extract_config(runner) do
    runner
    |> Map.take([
      :run_mode,
      :start_delay,
      :run_duration,
      :rest_duration,
      :post_pause_delay,
      :direction
    ])
    |> Map.put_new(:starting_position, 1)
  end

  defp simple_state({:stopped, reason}), do: {:stopped, reason}
  defp simple_state({state, _tref_or_remaining_ms}), do: state
  defp simple_state({state, _mode, _current_position}), do: state
  defp simple_state(state) when is_atom(state), do: state

  def build_state_snapshot(runner) do
    data =
      runner
      |> Map.from_struct()
      |> Map.put(:expected_duration, state_to_duration(runner, runner.state))
      |> Map.delete(:private)

    {data, runner.private.state_tag}
  end

  defp set_position(runner, pos) when is_integer(pos) do
    %{runner | position: pos}
  end

  defp set_next_position(%{direction: :forward, position: pos} = runner) do
    %{runner | position: pos + 1}
  end

  defp set_next_position(%{direction: :backward, position: pos} = runner) do
    %{runner | position: pos - 1}
  end

  defp state_to_duration(%{state: {paused_state, _tref}}, {:paused, {paused_state, remaining_ms}}) do
    remaining_ms
  end

  # TODO decipher state_to_duration
  defp state_to_duration(
         %{state: {paused_state, _tref}},
         {:unpausing, {_, {paused_state, remaining_ms}}}
       ) do
    remaining_ms
  end

  defp state_to_duration(%{state: :waiting}, _), do: nil
  defp state_to_duration(%{state: {:starting, _}, start_delay: dur}, _), do: dur
  defp state_to_duration(%{state: {:running, :manual, _}}, _), do: nil
  defp state_to_duration(%{state: {:unpausing, _}, post_pause_delay: dur}, _), do: dur
  # no such state
  defp state_to_duration(%{state: :running, run_duration: dur}, _), do: dur
  defp state_to_duration(%{state: {:running, _}, run_duration: dur}, _), do: dur
  defp state_to_duration(%{state: {:resting, _}, rest_duration: dur}, _), do: dur
  # no such state
  defp state_to_duration(%{state: :resting, rest_duration: dur}, _), do: dur
  # no such state?
  defp state_to_duration(%{state: :paused, post_pause_delay: dur}, _), do: dur

  defp state_to_duration(%{state: state}, _) do
    Logger.warn("Tringin.Runner unknown duration for #{inspect(state)} state")
    nil
  end

  defp put_private(%{private: private} = runner, key, value) do
    %{runner | private: Map.put(private, key, value)}
  end
end
