defmodule Tringin.ProgressBroadcaster.Events do
  @moduledoc false

  defmodule ProgressUpdate do
    defstruct [:id, :delta, :latest_state_tag]
  end
end
