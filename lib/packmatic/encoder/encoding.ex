defmodule Packmatic.Encoder.Encoding do
  @moduledoc false
  alias Packmatic.Manifest
  alias Packmatic.Source
  alias Packmatic.Compressor
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

  def encoding_next(%EncodingState{current: nil, remaining: [_ | _]} = state) do
    case encoding_entry_start(state) do
      {:cont, data, state} -> {:cont, data, state}
      {:error, reason} -> encoding_entry_start_error(state, reason)
    end
  end

  def encoding_next(%EncodingState{current: {_, source, _}} = state) do
    case Source.read(source) do
      :eof -> encoding_entry_eof(state)
      {:error, reason} -> encoding_entry_error(state, reason)
      {data, source} -> state |> encoding_next_source(source) |> encoding_next_data(data)
      data -> state |> encoding_next_data(data)
    end
  end

  def encoding_next(%EncodingState{remaining: []} = state) do
    :ok = Compressor.finalise(state.compressor)

    state
    |> Map.put(:compressor, nil)
    |> done()
  end

  defp encoding_next_source(state, source) do
    state |> Map.put(:current, put_elem(state.current, 1, source))
  end

  defp encoding_next_data(%EncodingState{} = state, data) do
    case data do
      <<>> -> encoding_next(state)
      [] -> encoding_next(state)
      data when is_binary(data) or is_list(data) -> encoding_entry_data(state, data)
    end
  end

  defp encoding_entry_start(%{current: nil, remaining: [entry | rest]} = state) do
    with {:ok, source} <- Source.build(entry.source),
         {:ok, data_file, compressor} <- Compressor.build(state.compressor, entry.method),
         entry_info = %EncodingState.EntryInfo{offset: state.bytes_emitted},
         data_header = Field.encode_local_file_header(entry),
         data = [data_header, data_file] do
      %{state | current: {entry, source, entry_info}, remaining: rest}
      |> Map.put(:compressor, compressor)
      |> Map.update!(:bytes_emitted, &(&1 + iolist_size(data)))
      |> Event.emit_entry_started(entry)
      |> data(data)
    end
  end

  defp encoding_entry_start_error(%{on_error: :skip, remaining: [entry | rest]} = state, reason) do
    %{state | encoded: [{entry, {:error, reason}} | state.encoded], remaining: rest}
    |> Event.emit_entry_failed(entry, reason)
    |> data([])
  end

  defp encoding_entry_start_error(%{on_error: :halt, remaining: [entry | rest]} = state, reason) do
    %{state | encoded: [{entry, {:error, reason}} | state.encoded], remaining: rest}
    |> Event.emit_entry_failed(entry, reason)
    |> Event.emit_stream_ended(reason)
    |> halt(reason)
  end

  defp encoding_entry_data(%{current: current} = state, data_uncompressed) do
    {entry, source, info} = current
    {:ok, data_compressed, compressor} = Compressor.next(state.compressor, data_uncompressed)
    info = %{info | checksum: crc32(info.checksum, data_uncompressed)}
    info = %{info | size_compressed: info.size_compressed + iolist_size(data_compressed)}
    info = %{info | size: info.size + iolist_size(data_uncompressed)}

    state
    |> Map.put(:current, {entry, source, info})
    |> Map.put(:compressor, compressor)
    |> Map.update!(:bytes_emitted, &(&1 + iolist_size(data_compressed)))
    |> Event.emit_entry_updated(entry, info)
    |> data(data_compressed)
  end

  defp encoding_entry_eof(%{current: {entry, _, info}} = state) do
    {:ok, data_compressed, compressor} = Compressor.close(state.compressor)
    info = %{info | size_compressed: info.size_compressed + iolist_size(data_compressed)}
    data_descriptor = Field.encode_local_data_descriptor(info)

    state
    |> Map.put(:current, nil)
    |> Map.put(:compressor, compressor)
    |> Map.update!(:encoded, &[{entry, {:ok, info}} | &1])
    |> Map.update!(:bytes_emitted, &(&1 + iolist_size([data_compressed, data_descriptor])))
    |> Event.emit_entry_completed(entry)
    |> data([data_compressed, data_descriptor])
  end

  defp encoding_entry_error(%{on_error: :skip, current: {entry, _, _}} = state, reason) do
    {:ok, _data_compressed, compressor} = Compressor.close(state.compressor)

    state
    |> Map.put(:current, nil)
    |> Map.put(:compressor, compressor)
    |> Map.update!(:encoded, &[{entry, {:error, reason}} | &1])
    |> Event.emit_entry_failed(entry, reason)
    |> data([])
  end

  defp encoding_entry_error(%{on_error: :halt, current: {entry, _, _}} = state, reason) do
    {:ok, _data_compressed, compressor} = Compressor.close(state.compressor)

    state
    |> Map.put(:current, nil)
    |> Map.put(:compressor, compressor)
    |> Event.emit_entry_failed(entry, reason)
    |> Event.emit_stream_ended(reason)
    |> halt(reason)
  end
end
