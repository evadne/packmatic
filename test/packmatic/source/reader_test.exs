defmodule Packmatic.Source.URL.ReaderTest do
  use ExUnit.Case, async: true
  import PackmaticTest.Builder
  alias Packmatic.Source.URL.Reader

  test "reader works" do
    {:url, url} = build_url_source()
    {:ok, _pid} = :gen_statem.start_link(Reader, {url, []}, [])
  end
end
