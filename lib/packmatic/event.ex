defmodule Packmatic.Event do
  @moduledoc """
  Represents Events that can be raised during the lifecycle of a Packmatic Stream being consumed.

  To listen for Events, you must pass a function reference to the `on_event:` option when calling
  `Packmatic.build_stream/2`. This function will be called at appropriate junctures in the
  lifecycle of a Stream being consumed.

  The Events will be called in the following order:

  1.  `Packmatic.Event.StreamStarted`: Sent when the Stream starts encoding.

  2.  `Packmatic.Event.EntryStarted`: Sent when the Stream starts encoding data for a new entry.

  3.  `Packmatic.Event.EntryUpdated`: Sent when the entry has initialised and some data has been
      read. This event will be sent on each iteration of `c:Packmatic.Source.read/1`.

  4.  `Packmatic.Event.EntryFailed`: Sent when the entry has failed to initialise (its Source
      returned an error during `c:Packmatic.Source.init/1`), in which case there would have been
      no `EntryUpdated` events, or when the entry has failed during the course of reading (its
      Source returned an error during `c:Packmatic.Source.read/1`).

  5.  `Packmatic.Event.EntryCompleted`: Sent when the entry has been fully encoded (its Source has
      returned EOF).

  6.  `Packmatic.Event.StreamEnded`: Sent when the Stream has completed journaling.

  Please note that more event types may be added in the future.
  """

  @typedoc """
  Represents an Event that will be passed to the handler.
  """
  @type event ::
          __MODULE__.StreamStarted.t()
          | __MODULE__.StreamEnded.t()
          | __MODULE__.EntryStarted.t()
          | __MODULE__.EntryUpdated.t()
          | __MODULE__.EntryFailed.t()
          | __MODULE__.EntryCompleted.t()

  @typedoc """
  Represents the callback function passed to the Encoder.

  The callback function takes 1 argument, which is the actual Event that is raised by Packmatic.
  The Event, `t:event/0`, is one of the pre-defined structs under the `Packmatic.Event` namespace.

  Please keep in mind that more events may be added in the future, so you should always include a
  fallback clause in your handler function.

  Handlers are called from the same process that the Stream is being iterated from, which allows
  you to control what happens to it. Should you not wish to interrupt the Encoder, return `:ok`.
  Otherwise, if you must, you may raise an exception, which will crash the Stream.
  """
  @type handler_fun :: (event -> :ok | no_return())

  alias Packmatic.Manifest
  alias Packmatic.Encoder

  defmodule StreamStarted do
    @moduledoc """
    Represents an Event that is raised when a new copy of Encoder, and therefore a new Stream, is
    started against the Manifest.
    """

    @type t :: %__MODULE__{
            stream_id: Encoder.stream_id()
          }

    @enforce_keys ~w(stream_id)a
    defstruct stream_id: nil
  end

  defmodule StreamEnded do
    @moduledoc """
    Represents an Event that is raised when the Encoder completes work. In case of normal
    completion, the reason will be set to `:done`, otherwise and in case of Source errors, the
    reason will be carried across. 
    """

    @type t :: %__MODULE__{
            stream_id: Encoder.stream_id(),
            reason: term(),
            stream_bytes_emitted: non_neg_integer()
          }

    @enforce_keys ~w(stream_id reason stream_bytes_emitted)a
    defstruct stream_id: nil, reason: nil, stream_bytes_emitted: 0
  end

  defmodule EntryStarted do
    @moduledoc """
    Represents an Event that is raised when the Encoder starts reading from a new Entry. The Entry
    is the same one as passed in the Manifest.
    """

    @type t :: %__MODULE__{
            stream_id: Encoder.stream_id(),
            entry: Manifest.Entry.t()
          }

    @enforce_keys ~w(stream_id entry)a
    defstruct stream_id: nil, entry: nil
  end

  defmodule EntryUpdated do
    @moduledoc """
    Represents an Event that is raised when the Encoder has made progress reading from the Entry.
    Usually, the Source will read iteratively so this messge can be raised quite frequently.
    """

    @type t :: %__MODULE__{
            stream_id: Encoder.stream_id(),
            entry: Manifest.Entry.t(),
            entry_bytes_read: non_neg_integer(),
            stream_bytes_emitted: non_neg_integer()
          }

    @enforce_keys ~w(stream_id entry entry_bytes_read stream_bytes_emitted)a
    defstruct stream_id: nil, entry: nil, entry_bytes_read: 0, stream_bytes_emitted: 0
  end

  defmodule EntryCompleted do
    @moduledoc """
    Represents an Event that is raised when the Encoder has completed reading from the Entry, i.e.
    when the Source has returned EOF.
    """

    @type t :: %__MODULE__{
            stream_id: Encoder.stream_id(),
            entry: Manifest.Entry.t()
          }

    @enforce_keys ~w(stream_id entry)a
    defstruct stream_id: nil, entry: nil
  end

  defmodule EntryFailed do
    @moduledoc """
    Represents an Event that is raised when the Encoder has failed to read from the Entry, i.e.
    when the Source has returned an error. Depending on the options, the Stream may continue to
    encode or it may halt.
    """

    @type t :: %__MODULE__{
            stream_id: Encoder.stream_id(),
            entry: Manifest.Entry.t(),
            reason: term()
          }

    @enforce_keys ~w(stream_id entry reason)a
    defstruct stream_id: nil, entry: nil, reason: nil
  end
end
