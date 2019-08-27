defmodule Packmatic.Encoder.JournalingState do
  @moduledoc false
  @type entry :: Packmatic.Manifest.Entry.t()
  @type entry_info :: Packmatic.Encoder.EncodingState.EntryInfo.t()

  @type t :: %__MODULE__{
          current: nil,
          remaining: [{entry, {:ok, entry_info} | {:error, term()}}],
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
