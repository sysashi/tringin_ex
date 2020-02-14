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

  def broadcast_message(runtime_opts, message) do
    with %{registry: registry, registry_prefix: prefix} <- runtime_opts do
      Registry.dispatch(registry, prefix, fn entries ->
        for {pid, {:listener, _}} <- entries do
          Process.send(pid, message, [:nosuspend])
        end
      end)
    end
  end
end
