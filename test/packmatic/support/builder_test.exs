defmodule Packmatic.Support.BuilderTest do
  use ExUnit.Case, async: true

  test "URL Source with notification" do
    source_module = Packmatic.Source.URL
    {:url, url} = PackmaticTest.Builder.build_url_source(2, :notify)
    {:ok, source} = source_module.init(url)

    assert :ok = consume(source_module, source, 1_048_576)
    assert_received {:chunked, 1_048_576}

    assert :ok = consume(source_module, source, 1_048_576)
    assert_received {:chunked, 2_097_152}

    assert :eof = consume(source_module, source, 1)
  end

  defp consume(source_module, source, bytes_needed, bytes_read \\ 0) do
    case source_module.read(source) do
      content when is_binary(content) ->
        bytes_read = bytes_read + byte_size(content)

        if bytes_read >= bytes_needed do
          :ok
        else
          consume(source_module, source, bytes_needed, bytes_read)
        end

      :eof ->
        :eof

      {:error, reason} ->
        {:error, reason}
    end
  end
end
