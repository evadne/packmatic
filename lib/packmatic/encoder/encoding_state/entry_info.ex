defmodule Packmatic.Encoder.EncodingState.EntryInfo do
  @moduledoc false
  @type t :: %__MODULE__{
          offset: non_neg_integer(),
          checksum: non_neg_integer(),
          size_compressed: non_neg_integer(),
          size: non_neg_integer()
        }

  @enforce_keys ~w(offset)a
  defstruct offset: 0, checksum: 0, size_compressed: 0, size: 0
end
