defmodule Tringin.Runner.Events do
  @moduledoc false

  defmodule Initialized do
    defstruct [:config]
  end

  defmodule StateTransition do
    defstruct [
      :id,
      :previous_state,
      :previous_state_tag,
      :new_state,
      :new_state_tag,
      :expected_state_duration,
      :current_position
    ]
  end

  defmodule ConfigChanged do
    defstruct [:id, :old_config, :new_config]
  end
end
