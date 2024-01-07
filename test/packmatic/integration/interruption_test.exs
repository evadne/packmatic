defmodule Packmatic.Integration.InterruptionTest do
  use ExUnit.Case, async: false
  import PackmaticTest.Builder
  import Mox

  setup :set_mox_from_context
  setup :verify_on_exit!
  defmock(__MODULE__.Source, for: Packmatic.Source)

  setup do
    {:ok, file_path} = Briefly.create()
    [file_path: file_path]
  end

  test "works with URL sources", context do
    # Given a Manifest containing 2 URL sources, each serving 5MB,
    # if only 1MB is read, the 2nd source is never used, so expect_once
    # should work.

    bypass = Bypass.open()
    size_mb = 10

    Bypass.expect_once(bypass, "GET", "/content.bin", fn conn ->
      build_byte_stream()
      |> Stream.take(size_mb)
      |> Packmatic.Conn.send_chunked(conn, "download.zip")
    end)

    [
      {{:url, "http://localhost:#{bypass.port}/content.bin"}, "a.bin"},
      {{:url, "http://localhost:#{bypass.port}/content.bin"}, "b.bin"}
    ]
    |> build_manifest()
    |> Packmatic.build_stream()
    |> Stream.into(File.stream!(context.file_path, [:write]))
    |> Enum.reduce_while(0, fn iodata, bytes ->
      with bytes = bytes + IO.iodata_length(iodata) do
        cond do
          bytes > 1_048_576 -> {:halt, bytes}
          true -> {:cont, bytes}
        end
      end
    end)

    on_exit({Bypass, bypass.pid}, fn ->
      # Assert that Bypass exited due to early termination of the consumer
      exit_condition = Bypass.Instance.call(bypass.pid, :on_exit)
      assert {:exit, {:exit, :shutdown, _}} = exit_condition
    end)
  end
end
