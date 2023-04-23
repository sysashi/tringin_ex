defmodule Tringin.LocalRegistry do
  @moduledoc false

  @behaviour Tringin.Registry.Behaviour

  alias __MODULE__

  defstruct [:name, :prefix]

  @type t :: %__MODULE__{
          name: pid() | atom(),
          prefix: atom() | binary()
        }

  def new(name, prefix)
      when is_atom(name) or (is_pid(name) and is_atom(prefix)) or is_binary(prefix) do
    %LocalRegistry{name: name, prefix: prefix}
  end

  def new(name, prefix) do
    msg = """

    registry name must be an atom or pid, got: #{inspect(name)}
    registry prefix must be an atom or string, got: #{inspect(prefix)}
    """

    raise ArgumentError, msg
  end

  def find_runner_process(%LocalRegistry{} = registry, role) do
    with [{pid, _}] <- Registry.match(registry.name, registry.prefix, role) do
      {:ok, pid}
    else
      [] ->
        {:error, :not_found}

      [_ | _] ->
        raise "Got multiple entries for the given role: #{inspect(role)}"

      _runtime_opts ->
        {:error, {:invalid, registry}}
    end
  end

  @impl Tringin.Registry.Behaviour
  def register_process(registry, role) do
    register_runner_process(registry, role)
  end

  def register_runner_process(%LocalRegistry{} = registry, role) do
    with [] <- Registry.match(registry.name, registry.prefix, role) do
      Registry.register(registry.name, registry.prefix, role)
    else
      [_] ->
        {:error, :already_exists}

      _runtime_opts ->
        {:error, {:invalid, registry}}
    end
  end

  def unregister_runner_process(%LocalRegistry{name: name, prefix: prefix}, role) do
    Registry.unregister_match(name, prefix, role)
  end

  @spec list_runner_processes(registry :: LocalRegistry.t()) :: Map.t()
  def list_runner_processes(%LocalRegistry{name: name, prefix: prefix}) do
    name
    |> Registry.lookup(prefix)
    |> Enum.map(fn {pid, role} -> {role, pid} end)
    |> Map.new()
  end

  @impl Tringin.Registry.Behaviour
  def broadcast(%LocalRegistry{name: name, prefix: prefix}, to, message) when is_list(to) do
    Registry.dispatch(name, prefix, fn entries ->
      for {pid, {role, _}} <- entries, role in to do
        Process.send(pid, message, [:nosuspend])
      end
    end)
  end
end
