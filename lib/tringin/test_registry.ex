defmodule TestRegistry do
  def register_process(registry, _role) when is_pid(registry) do
    {:ok, registry}
  end

  def register_process(registry, _role), do: {:error, {:invalid, registry}}

  def broadcast(pid, _roles, event) do
    send(pid, event)
    :ok
  end
end
