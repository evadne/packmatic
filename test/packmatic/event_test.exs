defmodule Packmatic.EventTest do
  use ExUnit.Case, async: true
  import PackmaticTest.Builder
  alias Packmatic.Event.StreamStarted
  alias Packmatic.Event.StreamEnded
  alias Packmatic.Event.EntryStarted
  alias Packmatic.Event.EntryUpdated
  alias Packmatic.Event.EntryCompleted
  alias Packmatic.Event.EntryFailed

  test "works without shenanigans" do
    parent = self()

    handler_fun = fn event ->
      :ok = Process.send(parent, event, [:noconnect, :nosuspend])
    end

    build_entries()
    |> build_manifest()
    |> Packmatic.build_stream(on_error: :skip, on_event: handler_fun)
    |> Stream.run()

    assert_receive %StreamStarted{stream_id: stream_id}

    refute_receive %EntryStarted{stream_id: ^stream_id, entry: %{path: "a"}}
    assert_receive %EntryFailed{stream_id: ^stream_id, entry: %{path: "a"}, reason: :enoent}

    assert_receive %EntryStarted{stream_id: ^stream_id, entry: %{path: "b"}}
    assert_entry_completed(stream_id, "b", 1_048_576)
    assert_receive %EntryCompleted{stream_id: ^stream_id, entry: %{path: "b"}}

    assert_receive %EntryStarted{stream_id: ^stream_id, entry: %{path: "c"}}
    assert_entry_completed(stream_id, "c", 1_048_576)
    assert_receive %EntryCompleted{stream_id: ^stream_id, entry: %{path: "c"}}

    assert_receive %EntryStarted{stream_id: ^stream_id, entry: %{path: "d"}}
    assert_entry_completed(stream_id, "d", 1_048_576)
    assert_receive %EntryCompleted{stream_id: ^stream_id, entry: %{path: "d"}}

    assert_receive %StreamEnded{stream_id: ^stream_id, reason: :done}

    refute_receive _
  end

  test "works with shenanigans" do
    parent = self()

    handler_fun = fn
      %EntryStarted{entry: %{path: "crash"}} -> raise "as you wish"
      event -> :ok = Process.send(parent, event, [:noconnect, :nosuspend])
    end

    assert_raise RuntimeError, fn ->
      (build_entries() ++ [{{:random, 1_048_576}, "crash"}])
      |> build_manifest()
      |> Packmatic.build_stream(on_error: :skip, on_event: handler_fun)
      |> Stream.run()
    end
  end

  defp build_entries do
    [
      {{:file, "not_found.bin"}, "a"},
      {build_file_source(1), "b"},
      {build_url_source(1), "c"},
      {{:random, 1_048_576}, "d"}
    ]
  end

  defp assert_entry_completed(stream_id, path, bytes) do
    assert_receive %EntryUpdated{stream_id: ^stream_id, entry: %{path: ^path}} = event

    cond do
      event.entry_bytes_read == bytes -> :ok
      true -> assert_entry_completed(stream_id, path, bytes)
    end
  end
end
