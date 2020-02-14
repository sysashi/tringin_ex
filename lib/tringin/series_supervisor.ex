defmodule Tringin.SeriesSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  # @required_runtime_opts [:registry, :registry_prefix]

  # make sure series is provided
  @impl true
  def init(opts) do
    runtime_opts = Keyword.fetch!(opts, :runtime_opts)

    series_runner_opts =
      opts
      |> Keyword.get(:series_runner_opts, [])
      |> Keyword.put(:runtime_opts, runtime_opts)

    input_agent_opts =
      opts
      |> Keyword.get(:input_agent_opts, [])
      |> Keyword.put(:runtime_opts, runtime_opts)

    children = [
      {Tringin.SeriesRunner, series_runner_opts},
      {Tringin.AnswersAgent, input_agent_opts}
    ]

    case Tringin.Runtime.register_series_process(runtime_opts, :series_supervisor) do
      {:ok, _} ->
        Supervisor.init(children, strategy: :rest_for_one)

      {:error, reason} ->
        IO.warn("Could not register series supervisor process, reason: #{inspect(reason)}")
        :ignore
    end
  end
end
