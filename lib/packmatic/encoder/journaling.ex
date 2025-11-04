defmodule Packmatic.Encoder.Journaling do
  @moduledoc false
  alias Packmatic.Encoder.EncodingState
  alias Packmatic.Encoder.JournalingState
  alias Packmatic.Encoder.Field
  alias Packmatic.Encoder.Event
  import :erlang, only: [iolist_size: 1]

  defp cont(state), do: {:cont, state}
  defp data(state, data), do: {:cont, data, state}
  defp done(_, data), do: {:done, data}

  @spec journaling_start(EncodingState.t()) ::
          {:cont, JournalingState.t()}

  @spec journaling_next(JournalingState.t()) ::
          {:cont, iodata(), JournalingState.t()}
          | {:done, iodata()}

  def journaling_start(state) do
    cont(%JournalingState{
      stream_id: state.stream_id,
      remaining: Enum.reverse(state.encoded),
      offset: state.bytes_emitted,
      on_event: state.on_event
    })
  end

  def journaling_next(%{current: nil, remaining: [{entry, {:ok, info}} | rest]} = state) do
    journaling_next(%{state | current: {entry, info}, remaining: rest})
  end

  def journaling_next(%{current: nil, remaining: [{_, {:error, _}} | rest]} = state) do
    journaling_next(%{state | remaining: rest})
  end

  def journaling_next(%{current: {entry, info}} = state) do
    data = Field.encode_central_file_header(entry, info)

    state
    |> Map.put(:current, nil)
    |> Map.update!(:entries_emitted, &(&1 + 1))
    |> Map.update!(:bytes_emitted, &(&1 + iolist_size(data)))
    |> data(data)
  end

  def journaling_next(%{remaining: []} = state) do
    data = Field.encode_central_directory_end(state)

    state
    |> Map.update!(:bytes_emitted, &(&1 + iolist_size(data)))
    |> Event.emit_stream_ended(:done)
    |> done(data)
  end
end
