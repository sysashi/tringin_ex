defmodule Tringin.InputAgent.SingleEntry do
  @moduledoc false

  @behaviour Tringin.InputAgent

  use GenServer

  require Logger

  alias Tringin.LocalRegistry

  alias Tringin.Runner.Events.{
    ConfigChanged,
    StateTransition
  }

  alias Tringin.InputAgent.Events.SubmittedInputs

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    registry = Keyword.fetch!(opts, :registry)

    init_state = %{
      state_tag: nil,
      inputs: %{},
      runner_state: nil,
      runner_rest_duration: nil,
      registry: registry
    }

    with {:ok, _} <-
           LocalRegistry.register_runner_process(registry, {:service, :input_agent}),
         {:ok, runner} <- LocalRegistry.find_runner_process(registry, :runner),
         {:ok, {%{state: runner_state, rest_duration: rest_dur}, state_tag}} <-
           Tringin.Runner.get_state(runner) do
      {:ok,
       %{
         init_state
         | runner_state: runner_state,
           state_tag: state_tag,
           runner_rest_duration: rest_dur
       }}
    else
      error ->
        {:stop, error, init_state}
    end
  end

  ## Handle Inputs

  @impl Tringin.InputAgent
  def handle_input(agent, {actor_id, input}) do
    GenServer.call(agent, {:submit_input, actor_id, input})
  end

  @impl true
  def handle_call({:submit_input, responder_id, input}, {_pid, _tag}, state) do
    case register_input(responder_id, input, state) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, {:already_registered, input}} ->
        {:reply, {:error, {:already_submitted, input}}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  ## Handle Runner Events

  @impl true
  def handle_info(%StateTransition{new_state: :running} = event, state) do
    if is_nil(state.runner_rest_duration) || state.runner_rest_duration <= 0 do
      broadcast_inputs(state)
    end

    state =
      state
      |> Map.put(:runner_state, :running)
      |> Map.put(:inputs, %{})
      |> Map.put(:state_tag, event.new_state_tag)

    {:noreply, state}
  end

  def handle_info(%StateTransition{new_state: :resting} = event, state) do
    broadcast_inputs(state)

    state =
      state
      |> Map.put(:runner_state, :resting)
      |> Map.put(:inputs, %{})
      |> Map.put(:state_tag, event.new_state_tag)

    {:noreply, state}
  end

  def handle_info(%StateTransition{} = event, state) do
    state =
      state
      |> Map.put(:runner_state, event.new_state)
      |> Map.put(:state_tag, event.new_state_tag)

    {:noreply, state}
  end

  def handle_info(%ConfigChanged{} = event, state) do
    state = Map.put(state, :runner_rest_duration, event.new_config.rest_duration)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    IO.warn("InputAgent ignoring msg: #{inspect(msg)}")
    {:noreply, state}
  end

  @type state :: Map.t()
  @spec register_input(responder_id :: any, input :: any, state) ::
          :ok | {:error, :already_registered} | {:error, state}
  def register_input(responder_id, input, %{inputs: inputs, runner_state: :running} = state) do
    case Map.fetch(inputs, responder_id) do
      :error ->
        {:ok, %{state | inputs: Map.put(inputs, responder_id, input)}}

      {:ok, input} ->
        {:error, {:already_registered, input}}
    end
  end

  def register_input(_, _, %{runner_state: runner_state}), do: {:error, runner_state}

  defp broadcast_inputs(state) do
    inputs_event = %SubmittedInputs{
      id: {self(), make_ref()},
      inputs: state.inputs,
      state_tag: state.state_tag
    }

    LocalRegistry.broadcast(
      state.registry,
      [:listener],
      inputs_event
    )
  end
end
