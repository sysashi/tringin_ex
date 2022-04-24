defmodule Tringin.SeriesRunner.Config do
  @moduledoc false

  defstruct series: nil,
            run_mode: :automatic,
            start_delay: 3000,
            run_duration: 20_000,
            rest_duration: 5000,
            post_pause_delay: 3000,
            series_registry: nil

  @type t :: %__MODULE__{
          series: any(),
          run_mode: :automatic | :manual,
          start_delay: nil | pos_integer(),
          run_duration: nil | pos_integer(),
          rest_duration: nil | pos_integer(),
          post_pause_delay: nil | pos_integer(),
          series_registry: Tringin.SeriesRegistry.t()
        }

  def new!(config \\ %{}) do
    __MODULE__
    |> struct(config)
    |> validate_run_mode!()
    |> validate_series_registry!()
  end

  defp validate_run_mode!(%{run_mode: mode} = config) when mode in [:automatic, :manual],
    do: config

  defp validate_run_mode!(%{run_mode: mode}) when is_atom(mode) do
    raise ArgumentError,
          "unsupported run_mode #{inspect(mode)}, supported mods are: :automatic and :manual"
  end

  defp validate_run_mode!(%{run_mode: mode}) do
    raise ArgumentError,
          "run_mode is required and must be one of :automatic or :manual, got: #{inspect(mode)}"
  end

  defp validate_series_registry!(%{series_registry: %Tringin.SeriesRegistry{}} = config),
    do: config

  defp validate_series_registry!(%{series_registry: registry}) do
    raise ArgumentError, "series registry must be provided, got: #{inspect(registry)}"
  end
end
