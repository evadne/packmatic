defmodule Packmatic.Encoder.EncodingState do
  @moduledoc false
  alias Packmatic.Manifest.Entry
  alias Packmatic.Source
  alias __MODULE__.EntryInfo

  @type entry_current :: {Entry.t(), Source.t(), EntryInfo.t()}
  @type entry_encoded :: {Entry.t(), {:ok, EntryInfo.t()} | {:error, term()}}

  @type t :: %__MODULE__{
          current: nil | entry_current,
          encoded: [entry_encoded],
          remaining: [Entry.t()],
          zstream: nil | :zlib.zstream(),
          bytes_emitted: non_neg_integer(),
          on_error: :skip | :halt
        }

  @enforce_keys ~w(remaining)a

  defstruct current: nil,
            encoded: [],
            remaining: [],
            zstream: nil,
            bytes_emitted: 0,
            on_error: :skip
end
