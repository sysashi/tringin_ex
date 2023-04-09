defmodule Tringin.Runner.Config do
  @moduledoc false

  @options_schema NimbleOptions.new!(
                    run_mode: [
                      type: {:in, [:manual, :automatic]},
                      default: :automatic,
                      doc:
                        "Accepts `:manual` or `:automatic` mode." <>
                          " If `:manual` mode is set, then all" <>
                          " durations and delays are ignored and user expected to " <>
                          "advance runner manually."
                    ],
                    starting_position: [
                      type: :pos_integer,
                      default: 1
                    ],
                    start_delay: [
                      type: {:or, [:pos_integer, nil]},
                      default: 3000,
                      doc: "Milliseconds or `nil`, setting `nil` will skip `:starting` state."
                    ],
                    run_duration: [
                      type: {:or, [:pos_integer, nil]},
                      default: 20_000,
                      doc:
                        "Milliseconds or `nil`, if `run_mode: :automatic` is set then value is required."
                    ],
                    rest_duration: [
                      type: {:or, [:pos_integer, nil]},
                      default: 5000,
                      doc: "Milliseconds or `nil`, setting `nil` will skip `:resting` state."
                    ],
                    post_pause_delay: [
                      type: {:or, [:pos_integer, nil]},
                      default: 3000,
                      doc: "Milliseconds or `nil`, setting `nil` will skip `:unpausing` state."
                    ],
                    direction: [
                      type: {:in, [:forward, :backward]},
                      default: :forward
                    ]
                  )

  @doc "Supported options:\n#{NimbleOptions.docs(@options_schema)}"
  def new!(opts) do
    NimbleOptions.validate!(opts, @options_schema)
  end
end
