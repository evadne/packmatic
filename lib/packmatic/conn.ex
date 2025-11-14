defmodule Packmatic.Conn do
  @moduledoc """
  Contains convenience functions which can be used to easily integrate a Zip stream with
  Plug-using applications such as Phoenix.
  """

  @doc """
  Convenience function which sends the stream to the conn. The content of the Stream will be sent
  with an appropriately configured `Content-Disposition` response header (as attachment), and the
  name provided will be encoded for maximum compatibility with browsers.

  The encoding strategy follows [RFC 2231](https://datatracker.ietf.org/doc/html/rfc2231#section-4)
  and [RFC 5987](https://datatracker.ietf.org/doc/html/rfc5987#section-3.2) so as to allow reliable
  use of Unicode-based file names.

  ## Examples

      stream
      |> Packmatic.Conn.send_chunked(conn, "download.zip")
  """

  def send_chunked(stream, conn, filename) do
    Enum.reduce_while(stream, chunk(conn, filename), &reduce_while/2)
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

  defp chunk(conn, filename) do
    {:module, module} = Code.ensure_loaded(Plug.Conn)

    conn
    |> module.put_resp_content_type("application/zip")
    |> module.put_resp_header("content-disposition", encode_header_value(filename))
    |> module.send_chunked(200)
  end

  defp reduce_while(chunk, conn) do
    {:module, module} = Code.ensure_loaded(Plug.Conn)

    case module.chunk(conn, chunk) do
      {:ok, conn} -> {:cont, conn}
      {:error, :closed} -> {:halt, conn}
    end
  end
end
