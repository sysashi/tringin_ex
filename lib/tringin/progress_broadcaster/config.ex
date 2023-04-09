defmodule Tringin.ProgressBroadcaster.Config do
  @moduledoc false

  @options_schema NimbleOptions.new!(
                    rate: [
                      type: :pos_integer,
                      default: 250,
                      doc: "Rate at which ProgressBroadcaster sends events, set in milliseconds"
                    ]
                  )

  @doc "Supported options:\n#{NimbleOptions.docs(@options_schema)}"
  def new!(opts) do
    NimbleOptions.validate!(opts, @options_schema)
  end
end
