defmodule Packmatic.Encoder.EncodingState do
  @moduledoc false
  @type entry :: Packmatic.Manifest.Entry.t()
  @type entry_source :: struct()
  @type entry_info :: __MODULE__.EntryInfo.t()

  @type t :: %__MODULE__{
          current: nil | {entry, entry_source, entry_info},
          encoded: [{entry, {:ok, entry_info} | {:error, term()}}],
          remaining: [entry],
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
