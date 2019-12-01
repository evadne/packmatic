defmodule Packmatic.Encoder do
  @moduledoc """
  Holds logic which can be used to put together a Zip file in an interative fashion, suitable for
  wrapping within a `Stream`. The format of Zip files emitted by `Packmatic.Encoder` is documented
  under the modules implementing the `Packmatic.Field` protocol.

  The Encoder is wrapped in `Stream.resource/3` for consumption as an Elixir Stream, under
  `Packmatic.build_stream/1`. Further, the Stream can be used with `Plug.Conn` to serve a chunked
  connection easily, as provided in `Packmatic.Conn.send_chunked/3`.

  The Encoder has three statuses:

  1.  **Encoding,** where each Entry within the Manifest is transformed to a Source, which is
      subsequently consumed.

      If the `on_error` option is set to `:skip` when building the stream, then sources which have
      raised error are skipped, although at this time portions of the source may have already been
      sent. Otherwise, and as the default behaviour, an uncaught exception will be raised and the
      consumer of the Stream will crash.

      During Encoding, content is dynamically deflated.
    
  2.  **Journaling,** where each _successfully encoded_ Entry is journaled again at the end of the
      archive, with the Central Directory structure.
      
      Both Zip and Zip64 formats are used for maximum flexibility.
    
      In case the `on_error` option is set to `:skip`, any source which has raised an error during
      its consumption will not be journaled. Due to the nature of streaming archives, this may
      still leave portions of unusable data within the archive.
    
  3.  **Done,** which is the terminal status.
  """

  alias Packmatic.Manifest
  alias Packmatic.Event
  alias Packmatic.Encoder.{Encoding, EncodingState, Journaling, JournalingState}

  @typedoc """
  Represents possible options to use with the Encoder.

  - `on_error` can be set to either `:skip` or `:halt`, which controls how the Encoder behaves
    when there is an erorr with one of the Sources.
    
  - `on_event` can be set to a function which will be called when events are raised by the Encoder
    during its lifecycle. See `Packmatic.Event` for further information.
  """
  @type option :: {:on_error, :skip | :halt} | {:on_event, Event.handler_fun()}

  @typedoc """
  Represents an unique identifier of the Stream in operation. This allows you to distinguish
  between multiple series of Events raised against the same Manifest in multiple Streams
  concurrently.
  """
  @opaque stream_id :: reference()

  @typedoc """
  Represents the intenral state used when encoding entries.
  """
  @opaque encoding_state :: EncodingState.t()

  @typedoc """
  Represents the internal state used when journaling entries.
  """
  @opaque journaling_state :: JournalingState.t()

  @spec stream_start(manifest, [option]) :: {:ok, :encoding, encoding_state}
        when manifest: Manifest.valid()

  @spec stream_start(manifest, [option]) :: {:error, manifest}
        when manifest: Manifest.invalid()

  @spec stream_next(:encoding, encoding_state) ::
          {:ok, iodata(), :encoding, encoding_state}
          | {:ok, iodata(), :journaling, journaling_state}
          | {:error, term()}

  @spec stream_next(:journaling, journaling_state) ::
          {:ok, iodata(), :journaling, journaling_state}
          | {:ok, iodata(), :done, nil}

  @spec stream_next(:done, nil) ::
          {:ok, :halt, :done, nil}

  @spec stream_after(:done, nil) ::
          :ok

  @doc """
  Starts the Stream.

  If the Manifest provided is invalid, the call will not succeed and the invalid Manifest will be
  returned.
  """
  def stream_start(manifest, options), do: stream_encoding_start(manifest, options)

  @doc """
  Iterates the Stream.

  When the Stream is in `:encoding` status, this function may continue encoding of the current
  item, or advance to the next item, or advance to the `:journaling` status when there are no
  further items to encode.

  When the Stream is in `:journaling` status, this function may continue journaling the next item,
  or advance to the `:done` status.

  When the Stream is in `:done` status, it can not be iterated further.
  """
  def stream_next(status, state)
  def stream_next(:encoding, state), do: stream_encoding_next(state)
  def stream_next(:journaling, state), do: stream_journaling_next(state)
  def stream_next(:done, nil), do: {:ok, :halt, :done, nil}

  @doc """
  Completes the Stream.
  """
  def stream_after(_status, _state), do: :ok

  defp stream_encoding_start(manifest, options) do
    case Encoding.encoding_start(manifest, options) do
      {:cont, state} -> {:ok, :encoding, state}
      {:halt, {:error, reason}} -> {:error, reason}
    end
  end

  defp stream_encoding_next(state) do
    case Encoding.encoding_next(state) do
      {:cont, data, state} -> {:ok, data, :encoding, state}
      {:done, state} -> stream_journaling_start(state)
      {:halt, {:error, reason}} -> {:error, reason}
    end
  end

  defp stream_journaling_start(state) do
    case Journaling.journaling_start(state) do
      {:cont, state} -> {:ok, [], :journaling, state}
    end
  end

  defp stream_journaling_next(state) do
    case Journaling.journaling_next(state) do
      {:cont, data, state} -> {:ok, data, :journaling, state}
      {:done, data} -> {:ok, data, :done, nil}
    end
  end
end
