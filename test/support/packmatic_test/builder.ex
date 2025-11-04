defmodule PackmaticTest.Builder do
  import ExUnit.Callbacks

  def build_byte_stream do
    Stream.repeatedly(fn -> :crypto.strong_rand_bytes(1_048_576) end)
  end

  def build_file_source(size_mb \\ 8) do
    {:ok, file_path} = Briefly.create()

    build_byte_stream()
    |> Stream.take(size_mb)
    |> Stream.into(File.stream!(file_path, [:write]))
    |> Stream.run()

    {:file, file_path}
  end

  def build_url_source(size_mb \\ 8) do
    bypass = Bypass.open()
    on_exit(fn -> Bypass.pass(bypass) end)

    content_fun = fn conn ->
      build_byte_stream()
      |> Stream.take(size_mb)
      |> Packmatic.Conn.send_chunked(conn, "download.zip")
    end

    Bypass.stub(bypass, "GET", "/content.bin", content_fun)
    {:url, "http://localhost:#{bypass.port}/content.bin"}
  end

  def build_manifest(list) do
    list
    |> Enum.map(&[source: elem(&1, 0), path: elem(&1, 1)])
    |> Packmatic.Manifest.create()
  end

  def build_bypass_partial do
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
        if count > 5 do
          PackmaticTest.SocketProxy.halt(proxy)
        end

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

  def build_bypass_not_found do
    not_found_fun = fn conn ->
      Plug.Conn.send_resp(conn, 404, "Not found")
    end

    bypass = Bypass.open()
    Bypass.stub(bypass, "GET", "/not_found.bin", not_found_fun)
    {:ok, "http://localhost:#{bypass.port}/not_found.bin"}
  end
end
