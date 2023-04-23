defmodule Tringin.RunnerTest do
  use ExUnit.Case, async: true

  alias Tringin.Runner, as: R

  alias Tringin.Runner.Events.{
    StateTransition,
    Initialized
  }

  describe "Runner" do
    test "sets defaults on start" do
      {:ok, runner} = R.start_link(registry: self())

      assert is_pid(runner)
      assert {:ok, {state, state_tag}} = R.get_state(runner)
      assert state_tag

      assert %{
               expected_duration: nil,
               run_duration: 20000,
               rest_duration: 5000,
               start_delay: 3000,
               state: :waiting
             } = state
    end
  end

  describe "Runner in manual mode" do
    test "starts in :waiting state" do
      runner_pid = start_runner(run_mode: :manual)
      assert {:ok, {%{state: :waiting}, _}} = R.get_state(runner_pid)
    end

    @tag skip: true
    test "transitions from :waiting state to :starting when game starts" do
      runner_pid = start_runner(run_mode: :manual)
      assert {:ok, _} = R.start(runner_pid)
      assert_state_transition(from: :waiting, to: :starting)
    end

    test "changes position by :next command" do
      runner_pid = start_runner(run_mode: :manual, start_delay: nil)

      assert {:ok, _} = R.start(runner_pid)
      event = assert_state_transition(from: :waiting, to: :running)
      assert event.current_position == 1

      for pos <- 2..10 do
        assert :ok = R.next(runner_pid)
        event = assert_state_transition(from: :running, to: :running)
        assert event.current_position == pos
      end
    end
  end

  describe "Runner in automatic mode" do
    test "starts in :waiting state" do
      runner_pid = start_runner()
      assert {:ok, {%{state: :waiting}, _}} = R.get_state(runner_pid)
    end

    test "transitions from :waiting state to :starting when runner starts" do
      runner_pid = start_runner()
      assert {:ok, _} = R.start(runner_pid)
      assert_state_transition(from: :waiting, to: :starting)
    end

    test "transitions from :waiting state to :running when start_delay is unspecified" do
      runner_pid = start_runner(start_delay: nil)
      assert {:ok, _} = R.start(runner_pid)
      assert_state_transition(from: :waiting, to: :running)
    end

    test "starting -> running -> resting" do
      config = runner_config()
      runner_pid = start_runner()
      assert {:ok, {%{state: :waiting}, _}} = R.start(runner_pid)

      assert_state_transition(from: :waiting, to: :starting, in: 10)
      assert_state_transition(from: :starting, to: :running, in: config[:start_delay])
      assert_state_transition(from: :running, to: :resting, in: config[:run_duration])
      assert_state_transition(from: :resting, to: :running, in: config[:rest_duration])
    end

    test "allows setting starting position" do
      runner_pid = start_runner(starting_position: 10)
      assert {:ok, {%{position: 10}, _}} = R.get_state(runner_pid)

      R.start(runner_pid)
      event = assert_state_transition(from: :waiting, to: :starting)
      assert event.current_position == 10
    end

    test "can be paused and unpaused in :starting state" do
      runner_pid = start_runner(start_delay: 1000)

      assert {:ok, _} = R.start(runner_pid)
      assert_state_transition(from: :waiting, to: :starting)

      assert :ok = R.pause(runner_pid)
      assert_state_transition(from: :starting, to: :paused)

      assert :ok = R.continue(runner_pid)
      assert_state_transition(from: :paused, to: :starting)
    end

    test "can be paused and unpaused in :running state" do
      runner_pid = start_runner(start_delay: nil, run_duration: 1000)

      assert {:ok, _} = R.start(runner_pid)
      assert_state_transition(from: :waiting, to: :running)

      assert :ok = R.pause(runner_pid)
      assert_state_transition(from: :running, to: :paused)

      assert :ok = R.continue(runner_pid)
      assert_state_transition(from: :paused, to: :running)
    end

    test "can be paused and unpaused in :resting state" do
      runner_pid = start_runner(start_delay: nil, run_duration: 1, rest_duration: 1000)

      assert {:ok, _} = R.start(runner_pid)
      assert_state_transition(from: :running, to: :resting)

      assert :ok = R.pause(runner_pid)
      assert_state_transition(from: :resting, to: :paused)

      assert :ok = R.continue(runner_pid)
      assert_state_transition(from: :paused, to: :resting)
    end

    test "pausing in paused state does nothing" do
      runner_pid = start_runner(start_delay: 1000)

      assert {:ok, _} = R.start(runner_pid)

      # Have to consume first message in order to catch anything else after pause
      assert_receive %Initialized{}
      assert_state_transition(from: :waiting, to: :waiting)
      assert_state_transition(from: :waiting, to: :starting)

      assert :ok = R.pause(runner_pid)
      assert_state_transition(from: :starting, to: :paused)
      {:ok, {_, state_tag_1}} = R.get_state(runner_pid)

      assert :ok = R.pause(runner_pid)
      {:ok, {_, state_tag_2}} = R.get_state(runner_pid)
      assert state_tag_1 == state_tag_2
      refute_receive _, 100
    end

    test "moves position automatically with resting step" do
      runner_pid = start_runner(start_delay: nil, rest_duration: 10, run_duration: 50)
      assert {:ok, _} = R.start(runner_pid)

      event = assert_state_transition(from: :waiting, to: :running)
      assert event.current_position == 1

      for pos <- 2..5 do
        event = assert_state_transition(from: :resting, to: :running)
        assert event.current_position == pos
      end

      assert {:ok, {%{position: 5}, _}} = R.get_state(runner_pid)
    end

    test "moves position automatically without resting step" do
      runner_pid = start_runner(start_delay: nil, rest_duration: nil, run_duration: 10)

      assert {:ok, _} = R.start(runner_pid)

      event = assert_state_transition(from: :waiting, to: :running)
      assert event.current_position == 1

      for pos <- 2..10 do
        event = assert_state_transition(from: :running, to: :running)
        assert event.current_position == pos
      end

      assert {:ok, {%{position: 10}, _}} = R.get_state(runner_pid)
    end

    test "allows restarting a runner" do
      runner_pid =
        start_runner(
          start_delay: nil,
          rest_duration: nil,
          run_duration: 10,
          starting_position: 10
        )

      assert {:ok, _} = R.start(runner_pid)
      event = assert_state_transition(from: :waiting, to: :running)
      assert event.current_position == 10

      assert :ok = R.restart(runner_pid)

      # Restart should respect starting position
      assert {:ok, {%{position: 1}, _}} = R.get_state(runner_pid)
      flunk("Restart should respect starting position")
    end
  end

  defp start_runner(opts \\ []) do
    {:ok, runner_pid} = start_supervised({R, runner_config(opts)})
    runner_pid
  end

  defp runner_config(overwrites \\ []) do
    config = [
      run_mode: :automatic,
      start_delay: 10,
      run_duration: 100,
      rest_duration: 100,
      post_pause_delay: nil,
      registry: self()
    ]

    Keyword.merge(config, overwrites)
  end

  defp assert_state_transition(args) do
    from = Keyword.fetch!(args, :from)
    to = Keyword.fetch!(args, :to)
    in_ms = Keyword.get(args, :in, 100)
    assert_receive event = %StateTransition{previous_state: ^from, new_state: ^to}, in_ms + 50
    event
  end
end
