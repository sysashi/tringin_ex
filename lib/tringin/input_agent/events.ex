defmodule Tringin.InputAgent.Events do
  @moduledoc false

  defmodule SubmittedInputs do
    defstruct id: nil, inputs: %{}, state_tag: nil
  end
end
