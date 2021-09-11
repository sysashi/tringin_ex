defmodule Tringin.SeriesRunnerTest do
  use ExUnit.Case, async: true

  alias Tringin.SeriesRunner, as: SR

  setup_all do
    {:ok, _} = start_supervised({Registry, keys: :duplicate, name: Tringin.RunnersTestRegistry})
    {:ok, runtime_opts: %{registry: Tringin.RunnersTestRegistry, registry_prefix: "test"}}
  end

  describe "series runner runtime" do
    test "sets defaults on start", c do
      {:ok, runner} = SR.start_link(runtime_opts: c.runtime_opts)

      assert is_pid(runner)
      assert {:ok, state} = SR.start_series(runner)

      assert %{
               expected_duration: 3000,
               question_duration: 20000,
               rest_duration: 5000,
               series: nil,
               start_delay: 3000,
               state: :ready,
               total_processed: 0
             } = state
    end
  end

  describe "series runner" do
    setup c do
      {:ok, runner} =
        start_supervised({
          SR,
          runtime_opts: %{c.runtime_opts | registry_prefix: c.test},
          question_duration: 50,
          start_delay: 0,
          rest_duration: 50
        })

      {:ok, runner: runner}
    end

    test "can start series", c do
      IO.inspect(c)
      runner = c.runner
      Tringin.Runtime.register_series_process(c.runtime_opts, {:listener, c.test})

      assert {:ok, %{state: :ready}} = SR.start_series(runner)
      assert_receive {:series_runner_update, %{state: :running}, {^runner, _}}, 100
    end
  end

  alias Tringin.SeriesRunnerExpirement, as: SRE

  describe "series runner based on gen_statem" do
    test "spawning and starting series runner", ctx do
      runner_config = runner_config(runtime_opts: ctx.runtime_opts)

      {:ok, runner_pid} = start_supervised({SRE, runner_config})

      Tringin.Runtime.register_series_process(ctx.runtime_opts, {:listener, :test})

      assert {:ok, {%{state: :waiting}, _}} = SRE.start_series(runner_pid)
      assert_receive {:runner_update, {%{state: :waiting}, _}, {^runner_pid, _}}, 10
      assert_receive {:runner_update, {%{state: :start_delay}, _}, {^runner_pid, _}}, 100
      assert_receive {:runner_update, {%{state: :running}, _}, {^runner_pid, _}}, 1000
    end
  end

  defp runner_config(overwrites \\ []) do
    config = [
      run_mode: :automatic,
      start_delay: 100,
      run_duration: 100,
      rest_duration: 100,
      post_pause_delay: 100
    ]

    Keyword.merge(config, overwrites)
  end
end
