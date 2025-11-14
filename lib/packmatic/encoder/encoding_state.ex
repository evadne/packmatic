defmodule Packmatic.Encoder.EncodingState do
  @moduledoc false
  alias Packmatic.Compressor
  alias Packmatic.Encoder
  alias Packmatic.Encoder.EncodingState.EntryInfo
  alias Packmatic.Event
  alias Packmatic.Manifest.Entry
  alias Packmatic.Source

  @type t :: %__MODULE__{
          stream_id: Encoder.stream_id(),
          current: nil | {Entry.t(), Source.t(), EntryInfo.t()},
          encoded: [{Entry.t(), {:ok, EntryInfo.t()} | {:error, term()}}],
          remaining: [Entry.t()],
          bytes_emitted: non_neg_integer(),
          compressor: nil | Compressor.t(),
          on_error: :skip | :halt,
          on_event: nil | Event.handler_fun()
        }

  @enforce_keys ~w(stream_id remaining)a

  defstruct stream_id: nil,
            current: nil,
            encoded: [],
            remaining: [],
            bytes_emitted: 0,
            compressor: nil,
            on_error: :skip,
            on_event: nil
end
