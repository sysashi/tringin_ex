# defmodule Tringin.SeriesRunnerExpirement do
#   @moduledoc """
#   ## States
#
#     * `:waiting`
#     * `:running`
#     * `:resting`
#     * `:paused`
#     * `:ended`
#
#   ## Events
#
#   `:start` start series if its not started
#   `:stop` restarts the series if its possible
#
#   `:pause` pauses at the next rest duration
#   `:force_pause` pauses running state at current duration (not implemented)
#
#   `:continue` runs series again if previous state was paused
#   `:restart_last` restarts last question if state was in :running or :force_paused (rename?)
#
#   `:reset` ? instead of restarts
#
#   ## Delays and Durations
#
#     * `:start_delay` delay before `:waiting` is changed to `:running`
#     * `:run_duration` duration of `:running` state
#     * `:rest_duration` delay before `:resting` is changed to `:running`
#     * `:post_pause_delay` delay before `:paused` transitioned to `:running`
#
#   ## Automatic Mode
#
#   Requires states timeouts to be set
#
#   ## Manual Mode
#
#   State Transitions will not happen automatically based on duration and delays. Runner will
#   accept additional set of events in order to progerss through series.
#
#     * `:move` moves series to next question (relative to current position)
#     * `{:move, n}` moves series to Nth question (relative to current position)
#     * `{:set, n}` moves series to Nth question
#
#   First approach would be to use generic timeouts and keep track of them,
#   so we would know how much left for the specific state to run and can
#   continue from that state for remaining timer
#
#   Second approach would be to skip need for keeping track of timeouts and
#   restart previous :waiting state
#   """
#
#   # :initialized
#   # :waiting (starting), waiting for a command
#   # :running
#   # :resting
#   # :paused (next state: resting | running)
#   # :ended
#
#   # waiting <- start (unless start_delay not set)
#   # ended <- restart, move
#   # running <- pause, force_pause, stop, restart, end
#   # paused <- continue, stop, restart, end
#   # resting <- pause, force_pause, stop, restart, end
#
#   @behaviour :gen_statem
#
#   @registry Application.compile_env(:tringin_ex, :registry, Tringin.SeriesRegistry)
#
#   require Logger
#
#   alias Tringin.SeriesRunner.Events.{
#     ConfigChanged,
#     Initialized,
#     StateTransition
#   }
#
#   alias Tringin.SeriesRegistry
#
#   def child_spec(init_arg) do
#     %{
#       id: __MODULE__,
#       start: {__MODULE__, :start_link, [init_arg]}
#     }
#   end
#
#   defstruct series: nil,
#             run_mode: :automatic,
#             start_delay: 3000,
#             run_duration: 20_000,
#             rest_duration: 5000,
#             post_pause_delay: 0,
#             state: nil,
#             position: 1,
#             direction: :forward,
#             series_registry: nil,
#             private: %{
#               state_tag: {0, 0, 0}
#             }
#
#   ## Controls
#
#   def start_series(runner, config \\ []) do
#     :gen_statem.call(runner, {:start_series, config})
#   end
#
#   def start(runner) do
#     :gen_statem.call(runner, :start)
#   end
#
#   def stop(runner) do
#     :gen_statem.call(runner, :stop)
#   end
#
#   # FIXME
#   def restart(runner) do
#     :gen_statem.cast(runner, :reset_position)
#   end
#
#   def pause(runner) do
#     :gen_statem.cast(runner, :pause)
#   end
#
#   def continue(runner) do
#     :gen_statem.cast(runner, :continue)
#   end
#
#   def next(runner) do
#     :gen_statem.call(runner, :next)
#   end
#
#   def set(runner, n) do
#     :gen_statem.call(runner, {:set, n})
#   end
#
#   ## Util
#
#   def get_state(runner_pid) do
#     :gen_statem.call(runner_pid, :get_state)
#   end
#
#   @doc false
#   def start_link(opts) do
#     :gen_statem.start_link(__MODULE__, opts, [])
#   end
#
#   @impl true
#   def init(opts) do
#     registry = Keyword.fetch!(opts, :series_registry)
#
#     case @registry.register_process(registry, :series_runner) do
#       {:ok, _} ->
#         runner =
#           struct(__MODULE__, Keyword.delete(opts, :private))
#           |> put_private(:state_tag, gen_state_tag())
#
#         {:ok, :waiting, runner}
#
#       {:error, reason} ->
#         {:stop, reason}
#     end
#   end
#
#   @impl true
#   def callback_mode(), do: [:handle_event_function, :state_enter]
#
#   @impl true
#   def handle_event(:enter, old_state, new_state, runner) do
#     Logger.debug(
#       "Tringin.SeriesRunner transition from: #{inspect(old_state)} to: #{inspect(new_state)}"
#     )
#
#     # IO.inspect(
#     #   "from: #{inspect(simple_state(old_state))} to: #{inspect(simple_state(new_state))}, position: #{runner.position}"
#     # )
#
#     new_state_tag = gen_state_tag()
#     old_state_tag = runner.private.state_tag
#
#     runner =
#       runner
#       |> Map.put(:state, new_state)
#       |> put_private(:state_tag, new_state_tag)
#
#     {:keep_state, broadcast_state_transition(runner, old_state, old_state_tag, new_state)}
#   end
#
#   # FIXME currently setting this to 0 so the next time it runs its gonna be 1
#   def handle_event(:cast, :reset_position, _, runner) do
#     {:keep_state, set_position(runner, 1)}
#   end
#
#   ## Pause
#
#   def handle_event(:cast, :pause, {state, tref}, runner)
#       when state in [:starting, :running, :resting] do
#     case :erlang.cancel_timer(tref) do
#       remaining_ms when is_integer(remaining_ms) ->
#         {:next_state, {:paused, {state, remaining_ms}}, runner}
#
#       other ->
#         raise "Could not cancel timer at state: #{state}, got: #{other}"
#         {:next_state, {:paused, state}, runner}
#     end
#   end
#
#   def handle_event(:cast, :pause, _state, _runner) do
#     :keep_state_and_data
#   end
#
#   # def handle_event(:cast, :pause, :running, _runner) do
#   #   {:keep_state_and_data, [:postpone]}
#   # end
#
#   # def handle_event(:cast, :pause, state, runner) do
#   #   {:next_state, {:paused, state}, runner}
#   # end
#
#   ## Continue
#
#   def handle_event(_event_type, :continue, {:paused, {state, remaining_ms}}, runner) do
#     next_event =
#       if runner.post_pause_delay && runner.post_pause_delay >= 0 do
#         {:unpausing, {start_timer(runner, :unpausing), {state, remaining_ms}}}
#       else
#         {state, start_timer(remaining_ms, state)}
#       end
#
#     {:next_state, next_event, runner}
#   end
#
#   def handle_event(:info, {:timeout, tref, _}, {:unpausing, {tref, paused}}, runner) do
#     {state, remaining_ms} = paused
#     {:next_state, {state, start_timer(remaining_ms, state)}, runner}
#   end
#
#   # def handle_event(:cast, :continue, {:paused, state}, _runner) do
#   #   IO.inspect("foo")
#   #   {:keep_state_and_data, {:state_timeout, 0, state}}
#   # end
#
#   def handle_event(_event_type, :continue, _state, _runner) do
#     :keep_state_and_data
#   end
#
#   # Starting series
#
#   def handle_event({:call, from}, :start, :waiting, %{run_mode: :automatic} = runner) do
#     next_event =
#       if runner.start_delay && runner.start_delay >= 0 do
#         {:starting, start_timer(runner, :starting)}
#       else
#         {:running, start_timer(runner, :running)}
#       end
#
#     {
#       :next_state,
#       next_event,
#       runner,
#       {:reply, from, {:ok, build_state_snapshot(runner)}}
#     }
#   end
#
#   def handle_event({:call, from}, :start, :waiting, %{run_mode: :manual} = runner) do
#     {
#       :next_state,
#       {:running, :manual, runner.position},
#       runner,
#       {:reply, from, {:ok, build_state_snapshot(runner)}}
#     }
#   end
#
#   def handle_event({:call, from}, :start, {:paused, _}, _runner) do
#     {:keep_state_and_data, [{:reply, from, :ok}, {:next_event, :internal, :continue}]}
#   end
#
#   def handle_event({:call, from}, :start, _, _runner) do
#     {:keep_state_and_data, {:reply, from, {:error, :already_running}}}
#   end
#
#   def handle_event({:call, from}, :next, {:running, :manual, _}, runner) do
#     runner = set_next_position(runner)
#
#     {
#       :next_state,
#       {:running, :manual, runner.position},
#       runner,
#       {:reply, from, :ok}
#     }
#   end
#
#   def handle_event({:call, from}, :next, _state, _runner) do
#     {:keep_state_and_data, {:reply, from, {:error, :invalid_state}}}
#   end
#
#   def handle_event(:info, {:timeout, tref, _}, {:starting, tref}, runner) do
#     {
#       :next_state,
#       {:running, start_timer(runner, :running)},
#       runner
#     }
#   end
#
#   def handle_event(:info, {:timeout, tref, _}, {:running, tref}, runner) do
#     next_event =
#       if runner.rest_duration && runner.rest_duration >= 0 do
#         {:resting, start_timer(runner, :resting)}
#       else
#         {:running, start_timer(runner, :running)}
#       end
#
#     {
#       :next_state,
#       next_event,
#       runner
#     }
#   end
#
#   def handle_event(:info, {:timeout, tref, _}, {:resting, tref}, runner) do
#     {
#       :next_state,
#       {:running, start_timer(runner, :running)},
#       set_next_position(runner)
#     }
#   end
#
#   defp start_timer(duration, next_state) when is_integer(duration) do
#     :erlang.start_timer(
#       duration,
#       self(),
#       next_state
#     )
#   end
#
#   defp start_timer(runner, next_state) do
#     :erlang.start_timer(
#       timer_dur(runner, next_state),
#       self(),
#       next_state
#     )
#   end
#
#   def timer_dur(%{start_delay: dur}, :starting), do: dur
#   def timer_dur(%{run_duration: dur}, :running), do: dur
#   def timer_dur(%{rest_duration: dur}, :resting), do: dur
#   def timer_dur(%{post_pause_delay: dur}, :unpausing), do: dur
#
#   # def handle_event({:call, from}, :start, :waiting, runner) do
#   #   {
#   #     :keep_state_and_data,
#   #     [
#   #       {:state_timeout, runner.start_delay, {:run, runner.run_mode}},
#   #       {:reply, from, {:ok, build_state_snapshot(runner)}}
#   #     ]
#   #   }
#   # end
#
#   # def handle_event({:call, from}, :start, _state, _runner) do
#   #   {
#   #     :keep_state_and_data,
#   #     [
#   #       {:reply, from, {:error, :already_started}}
#   #     ]
#   #   }
#   # end
#
#   # start(pos \\ 1)
#   # set(pos)
#
#   # def handle_event({:call, from}, {:set, pos}, _state, runner) when pos >= 1 do
#   #   len = Tringin.SeriesProto.length(runner.series)
#
#   #   if pos <= len do
#   #     with {:ok, series} <- Tringin.SeriesProto.load_question(runner.series, pos) do
#   #       runner = %{runner | series: series}
#
#   #       case runner.run_mode do
#   #         :manual ->
#   #           {:next_state, :running, runner}
#
#   #         :automatic ->
#   #           {:next_state, :running, runner, {:state_timeout, runner.run_duration, :rest}}
#   #       end
#   #     end
#   #   else
#   #     {
#   #       :keep_state_and_data,
#   #       [
#   #         {:reply, from, {:error, :out_of_bounds}}
#   #       ]
#   #     }
#   #   end
#   # end
#
#   # Run series
#
#   ### Set position when run mode is manual
#
#   # def handle_event({:call, from}, {:set, pos}, {:running, :manual}, runner)
#   #     when is_integer(pos) do
#   #   {:next_state, {:running, :manual}, set_position(runner, pos), {:reply, from, :ok}}
#   # end
#
#   # def handle_event({:call, from}, {:set, _pos}, {:running, :manual}, _runner) do
#   #   {:keep_state_and_data, {:reply, from, {:error, :invalid_position}}}
#   # end
#
#   # ### Set position when run mode is automatic
#   # def handle_event({:call, _from}, {:set, _pos}, {:running, :automatic}, _runner) do
#   #   {:keep_state_and_data, [:postpone]}
#   # end
#
#   # ### restart timer?
#   # def handle_event({:call, from}, {:set, pos}, _state, runner) do
#   #   {:keep_state, set_position(runner, pos),
#   #    [
#   #      {:state_timeout, 0, {:run, runner.run_mode}},
#   #      {:reply, from, :ok}
#   #    ]}
#   # end
#
#   # def handle_event(:state_timeout, {:run, :manual}, :waiting, runner) do
#   #   {:next_state, {:running, :manual}, runner}
#   # end
#
#   # def handle_event(:state_timeout, {:run, :automatic}, state, runner)
#   #     when state in [:waiting, :resting] do
#   #   {:next_state, {:running, :automatic}, set_next_position(runner),
#   #    {:state_timeout, runner.run_duration, :rest}}
#   # end
#
#   # def handle_event(:state_timeout, {:running, :automatic}, state, runner) do
#   #   IO.inspect(state, lable: "state")
#
#   #   {:next_state, {:running, :automatic}, set_next_position(runner),
#   #    {:state_timeout, runner.run_duration, :rest}}
#   # end
#
#   # def handle_event(:state_timeout, :run, state, runner)
#   #     when state in [:waiting, :start_delay, :resting] do
#   #   with {:ok, series} <- Tringin.SeriesProto.load_next_question(runner.series) do
#   #     runner = %{runner | state: :running, series: series}
#
#   #     case runner.run_mode do
#   #       :manual ->
#   #         {:next_state, :running, runner}
#
#   #       :automatic ->
#   #         {:next_state, :running, runner, {:state_timeout, runner.run_duration, :rest}}
#   #     end
#   #   else
#   #     x ->
#   #       IO.warn(x)
#   #       :keep_state_and_data
#   #   end
#   # end
#
#   # def handle_event(:state_timeout, :rest, {:running, :automatic}, runner) do
#   #   {:next_state, :resting, runner, {:state_timeout, runner.rest_duration, {:run, :automatic}}}
#   # end
#
#   # def handle_event(:state_timeout, :rest, :running, runner) do
#   #   {:next_state, :resting, runner, {:state_timeout, runner.rest_duration, :run}}
#   # end
#
#   # def handle_event(:state_timeout, :resting, state, runner) do
#   #   IO.inspect(state)
#   #   {:next_state, :resting, runner, {:state_timeout, runner.rest_duration, :run}}
#   # end
#
#   ## Util
#
#   def handle_event({:call, from}, :get_state, _state, runner) do
#     {:keep_state_and_data, {:reply, from, {:ok, build_state_snapshot(runner)}}}
#   end
#
#   def gen_state_tag(),
#     do: {
#       :erlang.monotonic_time(),
#       :erlang.unique_integer([:monotonic]),
#       :erlang.time_offset()
#     }
#
#   def broadcast_state_transition(runner, old_state, old_state_tag, new_state) do
#     event = %StateTransition{
#       id: {self(), make_ref()},
#       previous_state: simple_state(old_state),
#       previous_state_tag: old_state_tag,
#       new_state: simple_state(new_state),
#       new_state_tag: runner.private.state_tag,
#       expected_state_duration: state_to_duration(runner, old_state),
#       current_position: runner.position
#     }
#
#     @registry.broadcast(
#       runner.series_registry,
#       [:service, :listener],
#       event
#     )
#
#     runner
#   end
#
#   def broadcast_init(runner) do
#     event = %Initialized{
#       config: %{}
#     }
#   end
#
#   defp simple_state({state, _tref_or_remaining_ms}), do: state
#   defp simple_state({state, _mode, _current_position}), do: state
#   defp simple_state(state) when is_atom(state), do: state
#
#   def build_state_snapshot(runner) do
#     data =
#       runner
#       |> Map.from_struct()
#       |> Map.put(:expected_duration, state_to_duration(runner, runner.state))
#       |> Map.delete(:private)
#
#     {data, runner.private.state_tag}
#   end
#
#   defp set_position(runner, pos) when is_integer(pos) do
#     %{runner | position: pos}
#   end
#
#   defp set_next_position(%{direction: :forward, position: pos} = runner) do
#     %{runner | position: pos + 1}
#   end
#
#   defp set_next_position(%{direction: :backward, position: pos} = runner) do
#     %{runner | position: pos - 1}
#   end
#
#   defp put_private(%{private: private} = runner, key, value) do
#     %{runner | private: Map.put(private, key, value)}
#   end
#
#   defp state_to_duration(%{state: {paused_state, _tref}}, {:paused, {paused_state, remaining_ms}}) do
#     remaining_ms
#   end
#
#   defp state_to_duration(
#          %{state: {paused_state, _tref}},
#          {:unpausing, {_, {paused_state, remaining_ms}}}
#        ) do
#     remaining_ms
#   end
#
#   defp state_to_duration(%{state: :waiting}, _), do: nil
#   defp state_to_duration(%{state: {:starting, _}, start_delay: dur}, _), do: dur
#   defp state_to_duration(%{state: {:running, :manual, _}}, _), do: nil
#   defp state_to_duration(%{state: {:unpausing, _}, post_pause_delay: dur}, _), do: dur
#   # no such state
#   defp state_to_duration(%{state: :running, run_duration: dur}, _), do: dur
#   defp state_to_duration(%{state: {:running, _}, run_duration: dur}, _), do: dur
#   defp state_to_duration(%{state: {:resting, _}, rest_duration: dur}, _), do: dur
#   # no such state
#   defp state_to_duration(%{state: :resting, rest_duration: dur}, _), do: dur
#   # no such state?
#   defp state_to_duration(%{state: :paused, post_pause_delay: dur}, _), do: dur
#
#   defp state_to_duration(%{state: state}, _) do
#     Logger.warn("Tringin.SeriesRunner unknown duration for #{inspect(state)} state")
#     nil
#   end
# end
