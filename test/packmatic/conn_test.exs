defmodule Packmatic.ConnTest do
  use ExUnit.Case, async: true

  defmodule ClosingAdapter do
    defdelegate send_chunked(state, status, headers), to: Plug.Adapters.Test.Conn

    def chunk(%{chunks: ""} = state, body) do
      Plug.Adapters.Test.Conn.chunk(state, body)
    end

    def chunk(_state, _body), do: {:error, :closed}
  end

  test "preserves the three-argument API and attachment headers" do
    conn = Packmatic.Conn.send_chunked(["a", ["b", [?c]]], Plug.Test.conn(:get, "/"), "été.zip")

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.resp_body == "abc"
    assert ["application/zip; charset=utf-8"] == Plug.Conn.get_resp_header(conn, "content-type")

    assert ["attachment; filename*=UTF-8''%C3%A9t%C3%A9%2Ezip"] ==
             Plug.Conn.get_resp_header(conn, "content-disposition")
  end

  test "observes cumulative iodata reads before pulling the next chunk" do
    owner = self()

    stream =
      ["é", ["a", [?b, ["c"]]], [], "d"]
      |> Stream.with_index()
      |> Stream.map(fn {chunk, index} ->
        send(owner, {:pull, index})
        chunk
      end)

    conn =
      stream
      |> Stream.transform(0, fn chunk, total ->
        total = total + IO.iodata_length(chunk)
        send(owner, {:progress, total})
        {[chunk], total}
      end)
      |> Packmatic.Conn.send_chunked(Plug.Test.conn(:get, "/"), "a.zip")

    assert conn.resp_body == "éabcd"

    assert events(8) == [
             {:pull, 0},
             {:progress, 2},
             {:pull, 1},
             {:progress, 5},
             {:pull, 2},
             {:progress, 5},
             {:pull, 3},
             {:progress, 6}
           ]
  end

  test "does not report progress for an empty stream" do
    owner = self()

    conn =
      []
      |> Stream.transform(0, fn chunk, total ->
        total = total + IO.iodata_length(chunk)
        send(owner, {:progress, total})
        {[chunk], total}
      end)
      |> Packmatic.Conn.send_chunked(Plug.Test.conn(:get, "/"), "a.zip")

    assert conn.resp_body == ""
    refute_received {:progress, _}
  end

  test "counts the last chunk read on a closed connection and stops pulling" do
    conn = Plug.Test.conn(:get, "/")
    {_adapter, state} = conn.adapter
    conn = %{conn | adapter: {ClosingAdapter, state}}
    owner = self()

    stream =
      Stream.resource(
        fn -> 0 end,
        fn index ->
          send(owner, {:pull, index})
          {["ab"], index + 1}
        end,
        fn _state -> send(owner, :finalised) end
      )

    conn =
      stream
      |> Stream.transform(0, fn chunk, total ->
        total = total + IO.iodata_length(chunk)
        send(owner, {:progress, total})
        {[chunk], total}
      end)
      |> Packmatic.Conn.send_chunked(conn, "a.zip")

    assert conn.resp_body == "ab"
    assert events(5) == [{:pull, 0}, {:progress, 2}, {:pull, 1}, {:progress, 4}, :finalised]
    refute_received {:progress, _}
    refute_received {:pull, _}
  end

  test "streams an actual Packmatic archive with the reported byte count" do
    stream = Packmatic.build_stream([[source: {:stream, ["hello"]}, path: "greeting.txt"]])
    owner = self()

    conn =
      stream
      |> Stream.transform(0, fn chunk, total ->
        total = total + IO.iodata_length(chunk)
        send(owner, {:progress, total})
        {[chunk], total}
      end)
      |> Packmatic.Conn.send_chunked(Plug.Test.conn(:get, "/"), "a.zip")

    assert last_progress() == byte_size(conn.resp_body)
    assert {:ok, [{~c"greeting.txt", "hello"}]} = :zip.extract(conn.resp_body, [:memory])
  end

  test "reports reads locally while serving a URL stream" do
    owner = self()
    bypass = Bypass.open()
    chunk = :binary.copy(<<42>>, 1_048_576)

    Bypass.expect(bypass, "GET", "/content.bin", fn conn ->
      [chunk, chunk]
      |> Stream.transform(0, fn chunk, total ->
        total = total + IO.iodata_length(chunk)
        send(owner, {:progress, total})
        {[chunk], total}
      end)
      |> Packmatic.Conn.send_chunked(conn, "download.zip")
    end)

    assert {:ok, %Req.Response{status: 200, body: body}} =
             Req.get("http://localhost:#{bypass.port}/content.bin", raw: true)

    assert body == chunk <> chunk
    assert_receive {:progress, 1_048_576}
    assert_receive {:progress, 2_097_152}
    refute_received {:progress, _}
  end

  defp events(count) do
    for _ <- 1..count do
      receive do
        {:pull, _} = event -> event
        {:progress, _} = event -> event
        :finalised -> :finalised
      after
        100 -> flunk("missing stream event")
      end
    end
  end

  defp last_progress(total \\ nil) do
    receive do
      {:progress, next} -> last_progress(next)
    after
      0 -> total
    end
  end
end
