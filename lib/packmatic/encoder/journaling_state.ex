defmodule Packmatic.Encoder.JournalingState do
  @moduledoc false
  alias Packmatic.Event
  alias Packmatic.Manifest.Entry
  alias Packmatic.Encoder
  alias Packmatic.Encoder.EncodingState.EntryInfo

  @type t :: %__MODULE__{
          stream_id: Encoder.stream_id(),
          current: nil | {Entry.t(), EntryInfo.t()},
          remaining: [{Entry.t(), {:ok, EntryInfo.t()} | {:error, term()}}],
          offset: non_neg_integer(),
          entries_emitted: non_neg_integer(),
          bytes_emitted: non_neg_integer(),
          on_event: nil | Event.handler_fun()
        }

  @enforce_keys ~w(stream_id remaining offset)a

  defstruct stream_id: nil,
            current: nil,
            remaining: [],
            offset: 0,
            entries_emitted: 0,
            bytes_emitted: 0,
            on_event: nil
end
