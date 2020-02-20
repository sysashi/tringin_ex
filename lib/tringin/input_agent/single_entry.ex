defmodule Tringin.InputAgent.SingleEntry do
  @moduledoc false

  use GenServer

  alias Tringin.Runtime

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    runtime_opts = Keyword.fetch!(opts, :runtime_opts)

    init_state = %{
      state_tag: nil,
      answers: %{},
      runner_state: nil,
      runtime_opts: runtime_opts
    }

    with {:ok, _} <- Runtime.register_series_process(runtime_opts, {:service, :input_agent}),
         {:ok, runner} <- Runtime.find_series_process(runtime_opts, :series_runner),
         {:ok, {%{state: runner_state}, state_tag}} <- Tringin.SeriesRunner.get_state(runner) do
      {:ok, %{init_state | runner_state: runner_state, state_tag: state_tag}}
    else
      error ->
        {:stop, error, init_state}
    end
  end

  def handle_input(agent, {actor_id, input}) do
    GenServer.call(agent, {:submit_answer, actor_id, input})
  end

  def handle_call({:submit_answer, responder_id, answer}, {pid, _tag}, state) do
    case register_answer({responder_id, pid}, answer, state) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, {:already_registered, answer}} ->
        {:reply, {:error, {:already_submitted, answer}}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_info({:runner_update, {%{state: :running}, state_tag}, _}, state) do
    {:noreply, %{state | runner_state: :running, answers: %{}, state_tag: state_tag}}
  end

  def handle_info({:runner_update, {%{state: :resting}, state_tag}, _}, state) do
    message = {
      :input_agent_update,
      {:submitted_answers, state.answers, state.state_tag},
      {self(), make_ref()}
    }

    Tringin.Runtime.broadcast(
      state.runtime_opts,
      [:listener],
      message
    )

    {:noreply, %{state | runner_state: :resting, answers: %{}, state_tag: state_tag}}
  end

  def handle_info({:runner_update, {%{state: runner_state}, state_tag}, _}, state) do
    {:noreply, %{state | runner_state: runner_state, state_tag: state_tag}}
  end

  @type state :: Map.t()
  @spec register_answer(responder_id :: any, answer :: any, state) ::
          :ok | {:error, :already_registered} | {:error, state}
  def register_answer(responder_id, answer, %{answers: answers, runner_state: :running} = state) do
    case Map.fetch(answers, responder_id) do
      :error ->
        {:ok, %{state | answers: Map.put(answers, responder_id, answer)}}

      {:ok, answer} ->
        {:error, {:already_registered, answer}}
    end
  end

  def register_answer(_, _, %{runner_state: runner_state}), do: {:error, runner_state}
end
