defmodule Tringin.InputAgent do
  @callback handle_input(agent :: pid, {actor_id :: any, input :: binary}) ::
              :ok | {:error, any()}

  def handle_input(agent, {_, _} = params) do
    Tringin.InputAgent.SingleEntry.handle_input(agent, params)
  end
end
