defmodule Packmatic.Encoder.EncodingState do
  @moduledoc false
  alias Packmatic.Event
  alias Packmatic.Manifest.Entry
  alias Packmatic.Source
  alias Packmatic.Encoder
  alias Packmatic.Encoder.EncodingState.EntryInfo

  @type t :: %__MODULE__{
          stream_id: Encoder.stream_id(),
          current: nil | {Entry.t(), Source.t(), EntryInfo.t()},
          encoded: [{Entry.t(), {:ok, EntryInfo.t()} | {:error, term()}}],
          remaining: [Entry.t()],
          zstream: nil | :zlib.zstream(),
          bytes_emitted: non_neg_integer(),
          on_error: :skip | :halt,
          on_event: nil | Event.handler_fun()
        }

  @enforce_keys ~w(stream_id remaining)a

  defstruct stream_id: nil,
            current: nil,
            encoded: [],
            remaining: [],
            zstream: nil,
            bytes_emitted: 0,
            on_error: :skip,
            on_event: nil
end
