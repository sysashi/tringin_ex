defmodule Tringin.InputAgent.SingleEntry do
  @moduledoc false

  @behaviour Tringin.InputAgent

  use GenServer

  require Logger

  alias Tringin.SeriesRegistry
  alias Tringin.SeriesRunner.Events.StateTransition
  alias Tringin.InputAgent.Events.SubmittedInputs

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    series_registry = Keyword.fetch!(opts, :series_registry)

    init_state = %{
      state_tag: nil,
      inputs: %{},
      runner_state: nil,
      series_registry: series_registry
    }

    with {:ok, _} <-
           SeriesRegistry.register_series_process(series_registry, {:service, :input_agent}),
         {:ok, runner} <- SeriesRegistry.find_series_process(series_registry, :series_runner),
         {:ok, {%{state: runner_state}, state_tag}} <- Tringin.SeriesRunnerExpirement.get_state(runner) do
      {:ok, %{init_state | runner_state: runner_state, state_tag: state_tag}}
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
  def handle_call({:submit_input, responder_id, input}, {pid, _tag}, state) do
    case register_input({responder_id, pid}, input, state) do
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
    state =
      state
      |> Map.put(:runner_state, :running)
      |> Map.put(:inputs, %{})
      |> Map.put(:state_tag, event.new_state_tag)

    {:noreply, state}
  end

  def handle_info(%StateTransition{new_state: :resting} = event, state) do
    inputs_event = %SubmittedInputs{
      id: {self(), make_ref()},
      inputs: state.inputs,
      state_tag: state.state_tag
    }

    SeriesRegistry.broadcast(
      state.series_registry,
      [:listener],
      inputs_event
    )

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
end
