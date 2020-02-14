defmodule Tringin.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    Supervisor.start_link(
      [
        {Registry, keys: :duplicate, name: Tringin.RunnersRegistry}
      ],
      name: Tringin.Supervisor,
      strategy: :one_for_one
    )
  end
end
