defmodule Tringin do
  @moduledoc """
  Kinda useful helpers?
  """

  defdelegate init_series(source, params \\ []), to: Tringin.Series

  def register_series_listener(runtime_opts, listener_id) do
    Tringin.Runtime.register_series_process(runtime_opts, {:listener, listener_id})
  end

  def unregister_series_listener(runtime_opts, listener_id) do
    Tringin.Runtime.unregister_series_process(runtime_opts, {:listener, listener_id})
  end

  def list_series_processes(runtime_opts) do
    Tringin.Runtime.list_series_processes(runtime_opts.registry, runtime_opts.registry_prefix)
  end
end
