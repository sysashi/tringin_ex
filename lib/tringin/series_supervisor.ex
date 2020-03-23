defmodule Tringin.SeriesSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @core [
    {:runner, Tringin.SeriesRunner, []}
  ]

  @services [
    {:input_agent, Tringin.InputAgent.SingleEntry, []},
    {:progress_broadcaster, Tringin.ProgressBroadcaster, rate: 1000}
  ]

  # make sure series is provided
  @impl true
  def init(config) do
    runtime_opts = Keyword.fetch!(config, :runtime_opts)

    children =
      for {name, mod, default_opts} <- @core ++ @services do
        opts =
          default_opts
          |> Keyword.merge(config[name] || [])
          |> Keyword.put_new(:runtime_opts, runtime_opts)

        {mod, opts}
      end

    case Tringin.Runtime.register_series_process(runtime_opts, :series_supervisor) do
      {:ok, _} ->
        Supervisor.init(children, strategy: :rest_for_one)

      {:error, reason} ->
        IO.warn("Could not register series supervisor process, reason: #{inspect(reason)}")
        :ignore
    end
  end
end
