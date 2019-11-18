defmodule PackmaticTest do
  use ExUnit.Case, async: true
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
    # Given that the Entry has been created with a timestamp, the parsed timestamp from zipinfo
    # should be within 1 minute of the timestamp given.
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
    assert abs(timestamp_drift) < 60
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

    Bypass.expect(bypass, fn conn ->
      build_byte_stream()
      |> Stream.take(10)
      |> Packmatic.Conn.send_chunked(conn, "a.bin")
    end)

    [{{:url, "http://localhost:#{bypass.port}"}, "a.bin"}]
    |> build_manifest()
    |> Packmatic.build_stream()
    |> Stream.into(File.stream!(context.file_path, [:write]))
    |> Stream.run()
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
      %{status_code: 200, body: body} = HTTPotion.get(url)
      assert ["a", "b/c", "b/d"] == get_sorted_zip_files(body)
    end

    test "can download from existing URLs", context do
      urls = [
        "https://file-examples.com/wp-content/uploads/2017/11/file_example_MP3_700KB.mp3",
        "https://file-examples.com/wp-content/uploads/2017/11/file_example_OOG_1MG.ogg"
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
        {{:url, url_partial}, "partial.bin"}
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

  @tag external: true
  test "with large file", context do
    [{{:random, (4096 + 1) * 1_048_576}, "a"}]
    |> build_manifest()
    |> Packmatic.build_stream()
    |> Stream.into(File.stream!(context.file_path, [:write]))
    |> Stream.run()

    assert {_, 0} = System.cmd("zipinfo", [context.file_path])
  end

  defp build_byte_stream do
    Stream.repeatedly(fn -> :crypto.strong_rand_bytes(1_048_576) end)
  end

  defp build_file_source(size_mb \\ 8) do
    {:ok, file_path} = Briefly.create()

    build_byte_stream()
    |> Stream.take(size_mb)
    |> Stream.into(File.stream!(file_path, [:write]))
    |> Stream.run()

    {:file, file_path}
  end

  defp build_manifest(list) do
    Enum.reduce(list, Packmatic.Manifest.create(), fn {source, name}, manifest ->
      Packmatic.Manifest.prepend(manifest, path: name, source: source)
    end)
  end

  defp build_bypass_partial do
    #
    # For some reason, Bypass waits for the Plug serving partial data to finish, despite
    # the client having closed the socket reading from it. Mark the result as passed to avoid
    # hanging, since the function itself simply keeps feeding chunks indefinitely.

    bypass = Bypass.open()
    on_exit(fn -> Bypass.pass(bypass) end)
    {:ok, proxy} = PackmaticTest.SocketProxy.start(port: bypass.port)
    {:ok, partial_agent} = Agent.start_link(fn -> 0 end)

    partial_next_fun = fn _ ->
      Agent.update(partial_agent, fn count ->
        if count > 5, do: PackmaticTest.SocketProxy.halt(proxy)
        count + 1
      end)
    end

    partial_fun = fn conn ->
      build_byte_stream()
      |> Stream.each(partial_next_fun)
      |> Packmatic.Conn.send_chunked(conn, "partial.bin")
    end

    Bypass.stub(bypass, "GET", "/partial.bin", partial_fun)
    {:ok, "http://localhost:#{proxy.port}/partial.bin"}
  end

  defp build_bypass_not_found do
    not_found_fun = fn conn ->
      Plug.Conn.send_resp(conn, 404, "Not found")
    end

    bypass = Bypass.open()
    Bypass.stub(bypass, "GET", "/not_found.bin", not_found_fun)
    {:ok, "http://localhost:#{bypass.port}/not_found.bin"}
  end

  defp get_sorted_zip_files(target) do
    {:ok, zip_handle} = :zip.zip_open(target)
    {:ok, zip_list} = :zip.zip_list_dir(zip_handle)
    :ok = :zip.zip_close(zip_handle)

    for {:zip_file, name, _, _, _, _} <- zip_list do
      to_string(name)
    end
  end
end
