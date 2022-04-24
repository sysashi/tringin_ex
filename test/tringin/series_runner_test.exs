defmodule Tringin.SeriesRunnerTest do
  use ExUnit.Case, async: true

  alias Tringin.SeriesRunnerExpirement, as: SR

  setup_all do
    {:ok, _} =
      start_supervised({
        Registry,
        keys: :duplicate, name: Tringin.RunnersTestRegistry
      })

    {:ok, runtime_opts: %{registry: Tringin.RunnersTestRegistry, registry_prefix: "test"}}
  end

  setup ctx do
    {:ok, runtime_opts: %{ctx.runtime_opts | registry_prefix: ctx.test}}
  end

  describe "series runner runtime" do
    test "sets defaults on start", c do
      {:ok, runner} = SR.start_link(runtime_opts: c.runtime_opts)

      assert is_pid(runner)
      assert {:ok, {state, state_tag}} = SR.start_series(runner)
      assert state_tag

      assert %{
               expected_duration: 3000,
               run_duration: 20000,
               rest_duration: 5000,
               series: nil,
               start_delay: 3000,
               state: :waiting
             } = state
    end
  end

  describe "series runner based on gen_statem" do
    test "spawning and starting series runner", ctx do
      runner_config = runner_config(runtime_opts: ctx.runtime_opts, series: test_series())

      {:ok, runner_pid} = start_supervised({SR, runner_config})
      Process.link(runner_pid)

      Tringin.Runtime.register_series_process(ctx.runtime_opts, {:listener, ctx.test})

      assert {:ok, {%{state: :waiting}, _}} = SR.start_series(runner_pid)
      assert_receive {:runner_update, {%{state: :start_delay}, _}, {^runner_pid, _}}, 100
      assert_receive {:runner_update, {%{state: :running}, _}, {^runner_pid, _}}, 1000
    end
  end

  defmodule TestSeriesSource do
    @moduledoc false

    def next_question(_ctx, _extra), do: {:ok, "test question"}
  end

  defp test_series() do
    %Tringin.Series{
      source: __MODULE__.TestSeriesSource,
      source_context: %{}
    }
  end

  defp runner_config(overwrites \\ []) do
    config = [
      run_mode: :automatic,
      start_delay: 10,
      run_duration: 100,
      rest_duration: 100,
      post_pause_delay: 100
    ]

    Keyword.merge(config, overwrites)
  end
end
