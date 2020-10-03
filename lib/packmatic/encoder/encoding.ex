defmodule Packmatic.Encoder.Encoding do
  @moduledoc false
  alias Packmatic.Manifest
  alias Packmatic.Source
  alias Packmatic.Encoder
  alias Packmatic.Encoder.EncodingState
  alias Packmatic.Encoder.Field
  alias Packmatic.Encoder.Event
  import :erlang, only: [iolist_size: 1, crc32: 2]

  defp cont(state), do: {:cont, state}
  defp done(state), do: {:done, state}
  defp halt(_, reason), do: {:halt, {:error, reason}}
  defp data(state, data), do: {:cont, data, state}

  @spec encoding_start(Manifest.valid(), [Encoder.option()]) ::
          {:cont, EncodingState.t()}

  @spec encoding_start(Manifest.invalid(), [Encoder.option()]) ::
          {:halt, {:error, Manifest.t()}}

  @spec encoding_next(EncodingState.t()) ::
          {:cont, iodata(), EncodingState.t()}
          | {:done, EncodingState.t()}
          | {:halt, {:error, term()}}

  def encoding_start(%Manifest{valid?: true} = manifest, options) do
    id = make_ref()
    entries = manifest.entries
    on_error = Keyword.get(options, :on_error, :halt)
    on_event = Keyword.get(options, :on_event)

    %EncodingState{stream_id: id, remaining: entries, on_error: on_error, on_event: on_event}
    |> Event.emit_stream_started()
    |> cont()
  end

  def encoding_start(%Manifest{valid?: false} = manifest, _) do
    {:halt, {:error, manifest}}
  end

  def encoding_next(%EncodingState{current: nil, remaining: [entry | rest]} = state) do
    case Source.build(entry.source) do
      {:ok, source} -> encoding_entry_start(entry, source, %{state | remaining: rest})
      {:error, reason} -> encoding_entry_start_error(entry, reason, %{state | remaining: rest})
    end
  end

  def encoding_next(%EncodingState{current: {_, source, _}} = state) do
    case Source.read(source) do
      [] -> encoding_next(state)
      <<>> -> encoding_next(state)
      data when is_binary(data) or is_list(data) -> encoding_entry_data(data, state)
      :eof -> encoding_entry_eof(state)
      {:error, reason} -> encoding_entry_error(reason, state)
    end
  end

  def encoding_next(%EncodingState{remaining: []} = state) do
    state |> close_zstream() |> done()
  end

  defp encoding_entry_start(entry, source, state) do
    data = Field.encode_local_file_header(entry)
    info = %EncodingState.EntryInfo{offset: state.bytes_emitted}

    state
    |> reset_zstream()
    |> Map.put(:current, {entry, source, info})
    |> Map.update!(:bytes_emitted, &(&1 + iolist_size(data)))
    |> Event.emit_entry_started(entry)
    |> data(data)
  end

  defp encoding_entry_start_error(entry, reason, %{on_error: :skip} = state) do
    state
    |> Map.update!(:encoded, &[{entry, {:error, reason}} | &1])
    |> Event.emit_entry_failed(entry, reason)
    |> data([])
  end

  defp encoding_entry_start_error(entry, reason, %{on_error: :halt} = state) do
    state
    |> Map.update!(:encoded, &[{entry, {:error, reason}} | &1])
    |> Event.emit_entry_failed(entry, reason)
    |> Event.emit_stream_ended(reason)
    |> halt(reason)
  end

  defp encoding_entry_data(data_uncompressed, %{current: {entry, source, info}} = state) do
    data_compressed = :zlib.deflate(state.zstream, data_uncompressed, :full)
    info = %{info | checksum: crc32(info.checksum, data_uncompressed)}
    info = %{info | size_compressed: info.size_compressed + iolist_size(data_compressed)}
    info = %{info | size: info.size + iolist_size(data_uncompressed)}

    state
    |> Map.put(:current, {entry, source, info})
    |> Map.update!(:bytes_emitted, &(&1 + iolist_size(data_compressed)))
    |> Event.emit_entry_updated(entry, info)
    |> data(data_compressed)
  end

  defp encoding_entry_eof(%{current: {entry, _source, info}} = state) do
    data_compressed = :zlib.deflate(state.zstream, <<>>, :finish)
    info = %{info | size_compressed: info.size_compressed + iolist_size(data_compressed)}
    data_descriptor = Field.encode_local_data_descriptor(info)

    state
    |> Map.put(:current, nil)
    |> Map.update!(:encoded, &[{entry, {:ok, info}} | &1])
    |> Map.update!(:bytes_emitted, &(&1 + iolist_size([data_compressed, data_descriptor])))
    |> Event.emit_entry_completed(entry)
    |> data([data_compressed, data_descriptor])
  end

  defp encoding_entry_error(reason, %{current: {entry, _, _}, on_error: :skip} = state) do
    state
    |> Map.put(:current, nil)
    |> Map.update!(:encoded, &[{entry, {:error, reason}} | &1])
    |> Event.emit_entry_failed(entry, reason)
    |> data([])
  end

  defp encoding_entry_error(reason, %{current: {entry, _, _}, on_error: :halt} = state) do
    state
    |> Event.emit_entry_failed(entry, reason)
    |> Event.emit_stream_ended(reason)
    |> halt(reason)
  end

  defp reset_zstream(%{zstream: nil} = state) do
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

  defp reset_zstream(%{zstream: zstream} = state) do
    :ok = :zlib.deflateReset(zstream)
    state
  end

  defp close_zstream(%{zstream: nil} = state) do
    state
  end

  defp close_zstream(%{zstream: zstream} = state) do
    :ok = :zlib.close(zstream)
    %{state | zstream: nil}
  end
end
