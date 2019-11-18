defmodule Packmatic.Encoder.JournalingState do
  @moduledoc false
  alias Packmatic.Encoder.EncodingState

  @type t :: %__MODULE__{
          current: nil,
          remaining: [EncodingState.entry_encoded()],
          offset: non_neg_integer(),
          entries_emitted: non_neg_integer(),
          bytes_emitted: non_neg_integer()
        }

  @enforce_keys ~w(remaining offset)a

  defstruct current: nil,
            remaining: [],
            offset: 0,
            entries_emitted: 0,
            bytes_emitted: 0
end
