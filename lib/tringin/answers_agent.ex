defmodule Tringin.AnswersAgent do
  @moduledoc false

  use GenServer

  alias Tringin.Runtime

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    runtime_opts = Keyword.fetch!(opts, :runtime_opts)

    init_state = %{
      answers: %{},
      runner_state: nil,
      runtime_opts: runtime_opts
    }

    with {:ok, _} <- Runtime.register_series_process(runtime_opts, :input_agent),
         {:ok, runner} <- Runtime.find_series_process(runtime_opts, :series_runner),
         {:ok, %{state: runner_state}} <- Tringin.SeriesRunner.subscribe(runner) do
      {:ok, %{init_state | runner_state: runner_state}}
    else
      error ->
        {:stop, error, init_state}
    end
  end

  def submit_answer(agent, responder_id, answer) do
    GenServer.call(agent, {:submit_answer, responder_id, answer})
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

  def handle_info({:series_runner_update, %{state: :running}, _}, state) do
    {:noreply, %{state | runner_state: :running, answers: %{}}}
  end

  def handle_info({:series_runner_update, %{state: :resting}, _}, state) do
    # for {{submitter_pid, responder_id}, answer} <- state.answers do
    #   Process.send(
    #     submitter_pid,
    #     {:submitted_answer, {responder_id, answer}, {self(), make_ref()}},
    #     [:nosuspend]
    #   )
    # end

    :ok =
      Tringin.Runtime.broadcast_message(
        state.runtime_opts,
        {:input_agent_update, {:submitted_answers, state.answers}}
      )

    {:noreply, %{state | runner_state: :resting, answers: %{}}}
  end

  def handle_info({:series_runner_update, %{state: runner_state}, _}, state) do
    {:noreply, %{state | runner_state: runner_state}}
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
