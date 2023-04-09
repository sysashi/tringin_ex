defmodule Tringin.Registry.Behaviour do
  @type role :: :series_runner | :service | :listener
  @type registry :: any()
  @type event :: any()

  @callback register_process(registry(), role()) ::
              {:ok, pid()} | {:error, :already_exists} | {:error, {:invalid, any()}}

  @callback broadcast(registry(), [role(), ...], event()) :: :ok
end
