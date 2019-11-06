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
  alias Packmatic.Source
  alias Packmatic.Field
  alias __MODULE__.EncodingState
  alias __MODULE__.JournalingState

  @type option :: {:on_error, :skip | :halt}
  @type ok_start_encoding :: {:ok, :encoding, EncodingState.t()}
  @type ok_encoding :: {:ok, iolist(), :encoding, EncodingState.t()}
  @type ok_journaling :: {:ok, iolist(), :journaling, JournalingState.t()}
  @type ok_done :: {:ok, iolist(), :done, nil}
  @type ok_halt :: {:ok, :halt, :done, nil}
  @type error :: {:error, term()}

  @spec stream_start(Manifest.valid(), [option]) :: ok_start_encoding
  @spec stream_start(Manifest.invalid(), [option]) :: {:error, %Manifest{valid?: false}}
  @spec stream_next(:encoding, EncodingState.t()) :: ok_encoding | ok_journaling | error
  @spec stream_next(:journaling, JournalingState.t()) :: ok_journaling | ok_done
  @spec stream_next(:done, nil) :: ok_halt
  @spec stream_after(:done, nil) :: :ok

  import :erlang, only: [iolist_size: 1]

  @doc """
  Starts the Stream.

  If the Manifest provided is invalid, the call will not succeed and the invalid Manifest will be
  returned.
  """
  def stream_start(manifest, options) do
    with %{valid?: true} <- manifest do
      on_error = Keyword.get(options, :on_error, :halt)
      {:ok, :encoding, %EncodingState{remaining: manifest.entries, on_error: on_error}}
    else
      manifest -> {:error, manifest}
    end
  end

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
  def stream_next(:encoding, %EncodingState{} = state), do: stream_encode(state)
  def stream_next(:journaling, %JournalingState{} = state), do: stream_journal(state)
  def stream_next(:done, nil), do: {:ok, :halt, :done, nil}

  @doc """
  Completes the Stream.
  """
  def stream_after(_status, _state), do: :ok

  defp stream_encode(%{current: nil, remaining: [entry | rest]} = state) do
    case Source.build(entry.source) do
      {:ok, source} -> stream_encode_start(entry, source, %{state | remaining: rest})
      {:error, reason} -> stream_encode_start_error(entry, reason, %{state | remaining: rest})
    end
  end

  defp stream_encode(%{current: {_, source, _}} = state) do
    case Source.read(source) do
      data when is_binary(data) -> stream_encode_data(data, state)
      :eof -> stream_encode_eof(state)
      {:error, reason} -> stream_encode_error(reason, state)
    end
  end

  defp stream_encode(%{remaining: []} = state) do
    state = zstream_close(state)
    state = %JournalingState{remaining: state.encoded, offset: state.bytes_emitted}
    {:ok, [], :journaling, state}
  end

  defp stream_encode_start(entry, source, state) do
    data = encode_local_file_header(entry)
    info = %EncodingState.EntryInfo{offset: state.bytes_emitted}
    state = zstream_reset(state)
    state = %{state | current: {entry, source, info}}
    stream_emit(data, :encoding, state)
  end

  defp stream_encode_start_error(entry, reason, %{on_error: :skip} = state) do
    state = %{state | encoded: [{entry, {:error, reason}} | state.encoded]}
    stream_emit([], :encoding, state)
  end

  defp stream_encode_start_error(_entry, reason, %{on_error: :halt}) do
    {:error, reason}
  end

  defp stream_encode_data(data, %{current: {entry, source, info}} = state) do
    data_compressed = :zlib.deflate(state.zstream, data, :full)
    info = %{info | checksum: :erlang.crc32(info.checksum, data)}
    info = %{info | size_compressed: info.size_compressed + iolist_size(data_compressed)}
    info = %{info | size: info.size + iolist_size(data)}
    state = %{state | current: {entry, source, info}}
    stream_emit([data_compressed], :encoding, state)
  end

  defp stream_encode_eof(%{current: {entry, _source, info}} = state) do
    data_compressed = :zlib.deflate(state.zstream, <<>>, :finish)
    info = %{info | size_compressed: info.size_compressed + iolist_size(data_compressed)}
    data_descriptor = encode_local_data_descriptor(info)
    state = %{state | current: nil, encoded: [{entry, {:ok, info}} | state.encoded]}
    stream_emit([[data_compressed, data_descriptor]], :encoding, state)
  end

  defp stream_encode_error(reason, %{current: {entry, _, _}, on_error: :skip} = state) do
    state = %{state | current: nil, encoded: [{entry, {:error, reason}} | state.encoded]}
    stream_emit([], :encoding, state)
  end

  defp stream_encode_error(reason, %{on_error: :halt}) do
    {:error, reason}
  end

  defp stream_journal(%{current: {entry, info}} = state) do
    data = encode_central_file_header(entry, info)
    state = %{state | current: nil, entries_emitted: state.entries_emitted + 1}
    stream_emit(data, :journaling, state)
  end

  defp stream_journal(%{current: nil, remaining: []} = state) do
    data = encode_central_directory_end(state)
    stream_emit(data, :done, nil)
  end

  defp stream_journal(%{current: nil, remaining: [{entry, {:ok, info}} | rest]} = state) do
    stream_journal(%{state | current: {entry, info}, remaining: rest})
  end

  defp stream_journal(%{current: nil, remaining: [{_, {:error, _}} | rest]} = state) do
    stream_journal(%{state | remaining: rest})
  end

  defp stream_emit(item, status, %{bytes_emitted: _} = state) do
    {:ok, item, status, %{state | bytes_emitted: state.bytes_emitted + iolist_size(item)}}
  end

  defp stream_emit(item, status, state) do
    {:ok, item, status, state}
  end

  defp zstream_reset(%{zstream: nil} = state) do
    # See Erlang/OTP source for :zip.put_z_file/10
    # See http://erlang.org/doc/man/zlib.html#deflateInit-1
    #
    # Quote:
    # > A negative WindowBits value suppresses the zlib header (and checksum)
    # > from the stream. Notice that the zlib source mentions this only as a
    # > undocumented feature.
    #
    # With the default WindowBits value of 15, deflate fails on macOS.

    zstream = :zlib.open()
    :ok = :zlib.deflateInit(zstream, :default, :deflated, -15, 8, :default)
    %{state | zstream: zstream}
  end

  defp zstream_reset(%{zstream: zstream} = state) do
    :ok = :zlib.deflateReset(zstream)
    state
  end

  defp zstream_close(%{zstream: nil} = state) do
    state
  end

  defp zstream_close(%{zstream: zstream} = state) do
    :ok = :zlib.close(zstream)
    %{state | zstream: nil}
  end

  defp encode_local_file_header(entry) do
    Field.encode(%Field.Local.FileHeader{
      path: entry.path,
      timestamp: entry.timestamp
    })
  end

  defp encode_local_data_descriptor(info) do
    Field.encode(%Field.Local.DataDescriptor{
      checksum: info.checksum,
      size_compressed: info.size_compressed,
      size: info.size
    })
  end

  defp encode_central_file_header(entry, info) do
    Field.encode(%Field.Central.FileHeader{
      offset: info.offset,
      path: entry.path,
      checksum: info.checksum,
      size_compressed: info.size_compressed,
      size: info.size,
      timestamp: entry.timestamp
    })
  end

  defp encode_central_directory_end(state) do
    Field.encode(%Field.Central.DirectoryEnd{
      entries_count: state.entries_emitted,
      entries_size: state.bytes_emitted,
      entries_offset: state.offset
    })
  end
end
