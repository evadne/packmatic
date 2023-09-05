defmodule Packmatic.Source.StreamTest do
  use ExUnit.Case, async: true
  doctest Packmatic.Source.Stream

  test "can work independently on binaries" do
    module = Packmatic.Source.Stream
    enum = StreamData.binary() |> Stream.take(5)
    {:ok, state} = module.init(enum)

    state =
      for _ <- 1..5, reduce: state do
        state ->
          {data, state} = module.read(state)
          assert is_binary(data)
          state
      end

    assert :eof = module.read(state)
  end

  test "can work on IO Lists" do
    module = Packmatic.Source.Stream
    enum = StreamData.iolist() |> Stream.take(5)
    {:ok, state} = module.init(enum)

    state =
      for _ <- 1..5, reduce: state do
        state ->
          {data, state} = module.read(state)
          assert is_binary(IO.iodata_to_binary(data))
          state
      end

    assert :eof = module.read(state)
  end

  test "can work independently on StringIO-backed stream" do
    module = Packmatic.Source.Stream

    {:ok, device} = StringIO.open("a string\nfoo")
    enum = IO.binstream(device, :line)

    {:ok, state} = module.init(enum)

    state =
      for _ <- 1..2, reduce: state do
        state ->
          {data, state} = module.read(state)
          assert is_binary(data)
          state
      end

    assert :eof = module.read(state)
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

    test "can work with term roundtrip", context do
      term = [%{"lat" => 1.1, "long" => 2.2}]
      enum = [:erlang.term_to_binary(term)]

      [{{:stream, enum}, "foo.bin"}]
      |> PackmaticTest.Builder.build_manifest()
      |> Packmatic.build_stream()
      |> Stream.into(File.stream!(context.file_path, [:write]))
      |> Stream.run()

      assert {_, 0} = System.cmd("zipinfo", [context.file_path])
      assert {binary, 0} = System.cmd("unzip", ["-p", context.file_path])
      assert ^term = :erlang.binary_to_term(binary)
    end

    test "can work with IO Lists", context do
      [{{:stream, [[<<?A>>, <<?B>>], <<?C>>, [<<?D>>]]}, "foo.bin"}]
      |> PackmaticTest.Builder.build_manifest()
      |> Packmatic.build_stream()
      |> Stream.into(File.stream!(context.file_path, [:write]))
      |> Stream.run()

      assert {_, 0} = System.cmd("zipinfo", [context.file_path])
      assert {"ABCD", 0} = System.cmd("unzip", ["-p", context.file_path])
    end

    test "can work with StringIO-backed stream" do
      {:ok, device} = StringIO.open("a string\nfoo")
      stream = IO.binstream(device, :line)

      [{{:stream, stream}, "foo.bin"}]
      |> PackmaticTest.Builder.build_manifest()
      |> Packmatic.build_stream()
      |> Stream.run()
    end
  end
end
