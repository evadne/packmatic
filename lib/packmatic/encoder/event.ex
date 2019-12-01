defmodule Packmatic.Encoder.Event do
  @moduledoc false
  alias Packmatic.Event.StreamStarted
  alias Packmatic.Event.StreamEnded
  alias Packmatic.Event.EntryStarted
  alias Packmatic.Event.EntryUpdated
  alias Packmatic.Event.EntryCompleted
  alias Packmatic.Event.EntryFailed

  def emit_stream_started(state) do
    emit(state, fn ->
      %StreamStarted{
        stream_id: state.stream_id
      }
    end)
  end

  def emit_stream_ended(state, reason) do
    emit(state, fn ->
      %StreamEnded{
        stream_id: state.stream_id,
        reason: reason,
        stream_bytes_emitted: state.bytes_emitted
      }
    end)
  end

  def emit_entry_started(state, entry) do
    emit(state, fn ->
      %EntryStarted{
        stream_id: state.stream_id,
        entry: entry
      }
    end)
  end

  def emit_entry_updated(state, entry, info) do
    emit(state, fn ->
      %EntryUpdated{
        stream_id: state.stream_id,
        entry: entry,
        entry_bytes_read: info.size,
        stream_bytes_emitted: state.bytes_emitted
      }
    end)
  end

  def emit_entry_completed(state, entry) do
    emit(state, fn ->
      %EntryCompleted{
        stream_id: state.stream_id,
        entry: entry
      }
    end)
  end

  def emit_entry_failed(state, entry, reason) do
    emit(state, fn ->
      %EntryFailed{
        stream_id: state.stream_id,
        entry: entry,
        reason: reason
      }
    end)
  end

  defp emit(%{on_event: nil} = state, _) do
    state
  end

  defp emit(%{on_event: handler_fun} = state, event_fun) do
    :ok = handler_fun.(event_fun.())
    state
  end
end
