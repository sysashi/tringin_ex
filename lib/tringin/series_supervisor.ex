defmodule Tringin.SeriesSupervisor do
  @moduledoc false

  require Logger

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @core [
    {:runner, Tringin.SeriesRunnerExpirement, []}
  ]

  @services [
    {:input_agent, Tringin.InputAgent.SingleEntry, []},
    {:progress_broadcaster, Tringin.ProgressBroadcaster, rate: 1000}
  ]

  # make sure series is provided
  @impl true
  def init(config) do
    runtime_opts = Keyword.fetch!(config, :runtime_opts)
    registry = Tringin.SeriesRegistry.new(runtime_opts.registry, runtime_opts.registry_prefix)

    children =
      for {name, mod, default_opts} <- @core ++ @services do
        opts =
          default_opts
          |> Keyword.merge(config[name] || [])
          |> Keyword.put_new(:runtime_opts, runtime_opts)
          |> Keyword.put_new(:series_registry, registry)

        {mod, opts}
      end

    case Tringin.SeriesRegistry.register_series_process(registry, :series_supervisor) do
      {:ok, _} ->
        Supervisor.init(children, strategy: :rest_for_one)

      {:error, reason} ->
        Logger.warn("Could not register series supervisor process, reason: #{inspect(reason)}")
        :ignore
    end
  end
end
