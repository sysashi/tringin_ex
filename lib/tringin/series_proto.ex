defprotocol Tringin.SeriesProto do
  @moduledoc """
  Tringin.Series protocol is used by Series Runner to operate on a given series at runtime.
  """

  @doc "Returns id of a series"
  @spec id(t) :: any()
  def id(series)

  @doc "Returns length of a series"
  @spec length(t) :: pos_integer()
  def length(series)

  def initialize(series)

  def restart(series)

  @doc "Returns current position (current question index) of a series"
  @spec get_current_position(t) :: pos_integer()
  def get_current_position(series)

  @doc "Returns a question from series at given position"
  @spec load_question(t, position :: pos_integer()) :: {:ok, any()} | {:error, :ended} | {:error, any()}
  def load_question(series, position)

  @doc """
  Returns next question from the series.
  This function is going to be used whenever length of the series is not defined
  """
  @spec load_next_question(t) :: {:ok, any()} | {:error, :ended} | {:error, any()}
  def load_next_question(series)
end
