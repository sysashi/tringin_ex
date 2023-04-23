defmodule Tringin.RunnerSupervisor do
  @moduledoc false

  require Logger

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @core [
    {:runner, Tringin.Runner, []}
  ]

  @services [
    {:input_agent, Tringin.InputAgent.SingleEntry, []},
    {:progress_broadcaster, Tringin.ProgressBroadcaster, []}
  ]

  @impl true
  def init(config) do
    registry = Keyword.fetch!(config, :registry)

    children =
      for {name, mod, default_opts} <- @core ++ @services do
        opts =
          default_opts
          |> Keyword.merge(config[name] || [])
          |> Keyword.put_new(:registry, registry)

        {mod, opts}
      end

    case Tringin.LocalRegistry.register_runner_process(registry, :runner_supervisor) do
      {:ok, _} ->
        Supervisor.init(children, strategy: :rest_for_one)

      {:error, reason} ->
        Logger.warn("Could not register series supervisor process, reason: #{inspect(reason)}")
        :ignore
    end
  end
end
