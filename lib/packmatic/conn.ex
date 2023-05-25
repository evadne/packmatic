if Code.ensure_loaded?(Plug.Conn) do
  defmodule Packmatic.Conn do
    @moduledoc """
    Contains convenience functions which can be used to easily integrate a Zip stream with
    Plug-using applications such as Phoenix.
    """

    @doc """
    Convenience function which sends the stream to the conn. The content of the Stream will be
    sent with an appropriately configured `Content-Disposition` response header (as attachment),
    and the name provided will be encoded for maximum compatibility with browsers.

    ## Examples

        stream
        |> Packmatic.Conn.send_chunked(conn, "download.zip")
    """

    alias Plug.Conn
    @type event_fun :: (bytes_sent :: non_neg_integer() -> :ok)

    def send_chunked(stream, conn, filename) do
      conn = build_conn(conn, filename)
      Enum.reduce_while(stream, conn, &reduce_while/2)
    end

    def send_chunked(stream, conn, filename, event_fun) do
      conn = build_conn(conn, filename)
      {conn, _, _} = Enum.reduce_while(stream, {conn, 0, event_fun}, &reduce_while/2)
      conn
    end

    defp encode_filename(value) do
      URI.encode(value, fn
        x when ?0 <= x and x <= ?9 -> true
        x when ?A <= x and x <= ?Z -> true
        x when ?a <= x and x <= ?z -> true
        _ -> false
      end)
    end

    defp encode_header_value(filename) do
      "attachment; filename*=UTF-8''" <> encode_filename(filename)
    end

    defp build_conn(conn, filename) do
      conn
      |> Conn.put_resp_content_type("application/zip")
      |> Conn.put_resp_header("content-disposition", encode_header_value(filename))
      |> Conn.send_chunked(200)
    end

    defp reduce_while(chunk, %Conn{} = conn) do
      case Conn.chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, :closed} -> {:halt, conn}
      end
    end

    defp reduce_while(chunk, {%Conn{} = conn, bytes_sent, event_fun}) do
      with {:ok, conn} <- Conn.chunk(conn, chunk) do
        bytes_sent = bytes_sent + byte_size(chunk)
        :ok = event_fun.(bytes_sent)
        {:cont, {conn, bytes_sent, event_fun}}
      else
        {:error, :closed} -> {:halt, {conn, bytes_sent, event_fun}}
      end
    end
  end
end
