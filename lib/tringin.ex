defmodule Tringin do
  @moduledoc """
  Kinda useful helpers?
  """

  alias Tringin.SeriesRegistry

  def register_series_listener(series_registry, listener_id) do
    SeriesRegistry.register_series_process(series_registry, {:listener, listener_id})
  end

  def unregister_series_listener(series_registry, listener_id) do
    SeriesRegistry.unregister_series_process(series_registry, {:listener, listener_id})
  end

  def list_series_processes(series_registry) do
    SeriesRegistry.list_series_processes(series_registry)
  end

  def find_service_process(series_registry, role) do
    SeriesRegistry.find_series_process(series_registry, {:service, role})
  end

  def start_series(series_registry) do
    with {:ok, runner} <- SeriesRegistry.find_series_process(series_registry, :series_runner) do
      Tringin.SeriesRunnerExpirement.start(runner)
    end
  end
end
