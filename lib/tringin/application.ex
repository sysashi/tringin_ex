defmodule Tringin.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    Logger.add_translator({GenStatemTranslator, :translate})

    Supervisor.start_link(
      [],
      name: Tringin.Supervisor,
      strategy: :one_for_one
    )
  end
end
