defmodule Tringin do
  @moduledoc """
  Kinda useful helpers?
  """

  import Tringin.Runtime

  def register_series_listener(runtime_opts, listener_id) do
    register_series_process(runtime_opts, {:listener, listener_id})
  end

  def unregister_series_listener(runtime_opts, listener_id) do
    unregister_series_process(runtime_opts, {:listener, listener_id})
  end

  def list_series_processes(runtime_opts) do
    list_series_processes(runtime_opts.registry, runtime_opts.registry_prefix)
  end

  def find_service_process(runtime_opts, role) do
    find_series_process(runtime_opts, {:service, role})
  end

  def start_series(runtime_opts) do
    with {:ok, runner} <- find_series_process(runtime_opts, :series_runner) do
      Tringin.SeriesRunner.start_series(runner)
    end
  end
end
