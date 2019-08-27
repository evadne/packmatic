defmodule Packmatic.Conn do
  @moduledoc """
  Contains convenience functions which can be used to easily integrate a Zip stream with
  Plug-using applications such as Phoenix.
  """

  @doc """
  Convenience function which sends the stream to the conn.

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

  defp chunk(conn, filename) do
    {:module, module} = Code.ensure_loaded(Plug.Conn)
    value = "attachment; filename*=UTF-8''" <> encode_filename(filename)

    conn
    |> module.put_resp_content_type("application/zip")
    |> module.put_resp_header("content-disposition", value)
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
