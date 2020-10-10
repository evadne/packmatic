defmodule Packmatic.Source.StreamTest do
  use ExUnit.Case, async: true
  doctest Packmatic.Source.Stream

  test "can work independently" do
    module = Packmatic.Source.Stream
    enum = StreamData.binary() |> Stream.take(5)
    {:ok, state} = module.init(enum)

    for _ <- 1..5 do
      data = module.read(state)
      assert is_binary(data)
    end

    assert :eof = module.read(state)
    refute Process.alive?(state.agent_pid)
  end

  describe "when in a manifest" do
    setup do
      enum = StreamData.binary() |> Stream.take(5)
      {:ok, file_path} = Briefly.create()
      [enum: enum, file_path: file_path]
    end

    test "can work if used directly", context do
      [{{:stream, context.enum}, "foo.bin"}]
      |> PackmaticTest.Builder.build_manifest()
      |> Packmatic.build_stream()
      |> Stream.into(File.stream!(context.file_path, [:write]))
      |> Stream.run()
    end

    test "can work if used in dynamic source", context do
      [{{:dynamic, fn -> {:ok, {:stream, context.enum}} end}, "foo.bin"}]
      |> PackmaticTest.Builder.build_manifest()
      |> Packmatic.build_stream()
      |> Stream.into(File.stream!(context.file_path, [:write]))
      |> Stream.run()
    end
  end
end
