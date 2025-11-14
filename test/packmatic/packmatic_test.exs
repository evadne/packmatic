defmodule PackmaticTest do
  use ExUnit.Case, async: true
  import __MODULE__.Builder

  doctest Packmatic

  setup do
    {:ok, file_path} = Briefly.create()
    [file_path: file_path]
  end

  test "with well-formed streams", context do
    Stream.repeatedly(&build_file_source/0)
    |> Enum.zip(["a ", "b/c", "b/d"])
    |> build_manifest()
    |> Packmatic.build_stream()
    |> Stream.into(File.stream!(context.file_path, [:write]))
    |> Stream.run()

    assert {_, 0} = System.cmd("zipinfo", [context.file_path])
  end

  test "with no entries", context do
    assert_raise Packmatic.StreamError, fn ->
      []
      |> build_manifest()
      |> Packmatic.build_stream()
      |> Stream.into(File.stream!(context.file_path, [:write]))
      |> Stream.run()
    end
  end

  test "with timestamp", context do
    #
    # Given that the Entry has been created with a timestamp, the parsed timestamp from zipinfo,
    # which has minute resolution, should be within 1 minute of the timestamp given.
    #
    # NB: tests text output from zipinfo, possibly fragile. Zip module in Erlang does not support
    # returning metadata, and has compatibility problems with Zip64, which is used by Packmatic,
    # so the test can’t be done with that.

    timestamp = DateTime.utc_now()
    entry = [source: build_file_source(), path: "test", timestamp: timestamp]

    Packmatic.Manifest.create()
    |> Packmatic.Manifest.prepend(entry)
    |> Packmatic.build_stream()
    |> Stream.into(File.stream!(context.file_path, [:write]))
    |> Stream.run()

    pattern = ~r/defN (\d{2}-[a-zA-Z]{3}-\d{2} \d{2}:\d{2})/
    assert {result, 0} = System.cmd("zipinfo", [context.file_path], env: [{"TZ", "UTC"}])
    assert [_, timestamp_string] = Regex.run(pattern, result)
    assert {:ok, timestamp_value} = Timex.parse(timestamp_string, "%y-%b-%d %H:%M", :strftime)
    timestamp_drift = DateTime.from_naive!(timestamp_value, "Etc/UTC") |> DateTime.diff(timestamp)
    assert abs(timestamp_drift) <= 60
  end

  test "with attributes", context do
    import Bitwise

    [
      [source: build_file_source(), path: "1"],
      [source: build_file_source(), path: "2", attributes: 0o123],
      [source: build_file_source(), path: "3", attributes: [0o456, uid: 0, gid: 0]]
    ]
    |> Packmatic.Manifest.create()
    |> Packmatic.build_stream()
    |> Stream.into(File.stream!(context.file_path, [:write]))
    |> Stream.run()

    {:ok, directory} = Briefly.create(type: :directory)
    options = [cwd: to_charlist(directory), extra: [:extended_timestamp, :uid_gid]]
    {:ok, files} = :zip.unzip(to_charlist(context.file_path), options)

    list =
      Enum.map(files, fn path ->
        path = to_string(path)
        {:ok, stat} = File.stat(path)
        {Path.relative_to(path, directory), stat}
      end)

    assert {_, %{mode: mode}} = List.keyfind(list, "1", 0)
    assert 0o644 = mode &&& 0o777

    assert {_, %{mode: mode}} = List.keyfind(list, "2", 0)
    assert 0o123 = mode &&& 0o777

    # uid and gid not set by :zip
    assert {_, %{mode: mode}} = List.keyfind(list, "3", 0)
    assert 0o456 = mode &&& 0o777
  end

  test "with different compression methods", context do
    [
      [source: build_file_source(), path: "1", method: :deflate],
      [source: build_file_source(), path: "2", method: :store],
      [source: build_file_source(), path: "3", method: {:deflate, level: :best_compression}],
      [source: build_file_source(), path: "4", method: :store],
      [source: build_file_source(), path: "5", method: {:deflate, level: :best_speed}]
    ]
    |> Packmatic.Manifest.create()
    |> Packmatic.build_stream()
    |> Stream.into(File.stream!(context.file_path, [:write]))
    |> Stream.run()

    {:ok, zip_handle} = :zip.zip_open(to_charlist(context.file_path), [:memory])
    {:ok, {_, result}} = :zip.zip_get(~c"1", zip_handle)
    assert 8_388_608 = :erlang.iolist_size(result)
    {:ok, {_, result}} = :zip.zip_get(~c"2", zip_handle)
    assert 8_388_608 = :erlang.iolist_size(result)
    {:ok, {_, result}} = :zip.zip_get(~c"3", zip_handle)
    assert 8_388_608 = :erlang.iolist_size(result)
    {:ok, {_, result}} = :zip.zip_get(~c"4", zip_handle)
    assert 8_388_608 = :erlang.iolist_size(result)
    {:ok, {_, result}} = :zip.zip_get(~c"5", zip_handle)
    assert 8_388_608 = :erlang.iolist_size(result)
    :ok = :zip.zip_close(zip_handle)
  end

  test "with dynamic invocations", context do
    dynamic_fun = fn ->
      PackmaticTest.InvocationTarget.perform()
    end

    dynamic_fail_fun = fn ->
      {:error, :not_found}
    end

    [{{:dynamic, dynamic_fun}, "now.txt"}, {{:dynamic, dynamic_fail_fun}, "later.txt"}]
    |> build_manifest()
    |> Packmatic.build_stream(on_error: :skip)
    |> Stream.into(File.stream!(context.file_path, [:write]))
    |> Stream.run()

    assert ["now.txt"] == get_sorted_zip_files(to_charlist(context.file_path))
    assert {_, 0} = System.cmd("zipinfo", [context.file_path])
  end

  test "with local URL stream", context do
    bypass = Bypass.open()
    body = build_byte_stream() |> Stream.take(10) |> Enum.to_list()

    Bypass.expect(bypass, fn conn ->
      Packmatic.Conn.send_chunked(body, conn, "a.bin")
    end)

    [{{:url, "http://localhost:#{bypass.port}"}, "a.bin"}]
    |> build_manifest()
    |> Packmatic.build_stream()
    |> Stream.into(File.stream!(context.file_path, [:write]))
    |> Stream.run()

    {:ok, zip_handle} = :zip.zip_open(to_charlist(context.file_path), [:memory])
    {:ok, result} = :zip.zip_get(~c"a.bin", zip_handle)
    :ok = :zip.zip_close(zip_handle)

    # Assert the 10MB file survives the roundtrip
    assert {~c"a.bin", unzipped_body} = result
    lhs = IO.iodata_to_binary(body)
    rhs = IO.iodata_to_binary(unzipped_body)
    assert lhs == rhs
    assert 10_485_760 == byte_size(lhs)
    assert 10_485_760 == byte_size(rhs)
  end

  describe "with URL streams" do
    test "can download from Bypass" do
      bypass = Bypass.open()

      Bypass.expect(bypass, fn conn ->
        Stream.repeatedly(&build_file_source/0)
        |> Enum.zip(["a", "b/c", "b/d"])
        |> build_manifest()
        |> Packmatic.build_stream()
        |> Packmatic.Conn.send_chunked(conn, "download.zip")
      end)

      url = "http://localhost:#{bypass.port}"
      {:ok, %Req.Response{status: 200, body: body}} = Req.get(url, raw: true)
      assert ["a", "b/c", "b/d"] == get_sorted_zip_files(IO.iodata_to_binary(body))
    end

    @tag external: true
    test "can download from existing URLs", context do
      urls = [
        "https://upload.wikimedia.org/wikipedia/commons/a/a9/Example.jpg",
        "https://upload.wikimedia.org/wikipedia/en/a/a9/Example.jpg"
      ]

      Enum.map(urls, &{{:url, &1}, Path.basename(URI.parse(&1).path)})
      |> build_manifest()
      |> Packmatic.build_stream()
      |> Stream.into(File.stream!(context.file_path, [:write]))
      |> Stream.run()
    end
  end

  describe "with broken URL streams" do
    #
    # Test two kinds of broken URL streams: those that close prematurely and those that return 404
    # instead of actual data. Due to design limitations, if the remote endpoint closes the
    # connection prematurely, the partial file will still be emitted.

    setup do
      {:ok, url_not_found} = build_bypass_not_found()
      {:ok, url_partial} = build_bypass_partial()

      entries = [
        {{:url, url_not_found}, "not_found.bin"},
        {{:url,
          {url_partial, [retry: false, receive_timeout: 1000, connect_options: [timeout: 5000]]}},
         "partial.bin"}
      ]

      [manifest: build_manifest(entries)]
    end

    test "works with on_error: skip", context do
      context.manifest
      |> Packmatic.build_stream(on_error: :skip)
      |> Stream.into(File.stream!(context.file_path, [:write]))
      |> Stream.run()

      assert [] == get_sorted_zip_files(to_charlist(context.file_path))
    end

    test "crashes by default", context do
      assert_raise Packmatic.StreamError, fn ->
        context.manifest
        |> Packmatic.build_stream()
        |> Stream.into(File.stream!(context.file_path, [:write]))
        |> Stream.run()
      end
    end
  end

  @tag :skip
  test "with many small files", context do
    List.duplicate({{:random, 1}, "a"}, 1_048_576)
    |> build_manifest()
    |> Packmatic.build_stream()
    |> Stream.into(File.stream!(context.file_path, [:write]))
    |> Stream.run()

    assert {_, 0} = System.cmd("zipinfo", [context.file_path])
  end

  @tag external: true
  test "with large file", context do
    # Using 8x 1GB random chunks
    IO.inspect(["starting large"])

    1..8
    |> Enum.map(fn x -> {{:random, 1024 * 1_048_576}, "#{x}.bin"} end)
    |> build_manifest()
    |> Packmatic.build_stream()
    |> Stream.into(File.stream!(context.file_path, [:write]))
    |> Stream.run()

    IO.inspect(["large file size is now", context.file_path, File.stat!(context.file_path)])
    File.cp(context.file_path, "/tmp/out2.zip")
    assert {_, 0} = System.cmd("zipinfo", [context.file_path])
  end

  defp get_sorted_zip_files(target) do
    get_zip_files(target) |> Enum.sort()
  end

  defp get_zip_files(target) do
    {:ok, zip_handle} = :zip.zip_open(target)
    {:ok, zip_list} = :zip.zip_list_dir(zip_handle)
    :ok = :zip.zip_close(zip_handle)

    for {:zip_file, name, _, _, _, _} <- zip_list do
      to_string(name)
    end
  end
end
