defmodule Tringin.Runtime do
  @moduledoc false

  def find_series_process(runtime_opts, role) do
    with %{registry: registry, registry_prefix: prefix} <- runtime_opts,
         [{pid, _}] <- Registry.match(registry, prefix, role) do
      {:ok, pid}
    else
      [] ->
        {:error, :not_found}

      [_ | _] ->
        raise "Got multiple entries for the given role: #{inspect(role)}"

      _runtime_opts ->
        {:error, {:invalid, runtime_opts}}
    end
  end

  def register_series_process(runtime_opts, role) do
    with %{registry: registry, registry_prefix: prefix} <- runtime_opts,
         [] <- Registry.match(registry, prefix, role) do
      Registry.register(registry, prefix, role)
    else
      [_] ->
        {:error, :already_exists}

      _runtime_opts ->
        {:error, {:invalid, runtime_opts}}
    end
  end

  def unregister_series_process(%{registry: registry, registry_prefix: prefix}, role) do
    Registry.unregister_match(registry, prefix, role)
  end

  @spec list_series_processes(registry :: atom(), prefix :: any()) :: Map.t()
  def list_series_processes(registry, prefix) do
    registry
    |> Registry.lookup(prefix)
    |> Enum.map(fn {pid, role} -> {role, pid} end)
    |> Map.new()
  end

  def broadcast(runtime_opts, to, message) when is_list(to) do
    Registry.dispatch(runtime_opts.registry, runtime_opts.registry_prefix, fn entries ->
      for {pid, {role, _}} <- entries, role in to do
        Process.send(pid, message, [:nosuspend])
      end
    end)
  end
end
