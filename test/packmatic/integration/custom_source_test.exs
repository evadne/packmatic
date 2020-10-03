defmodule Packmatic.Integration.CustomSourceTest do
  use ExUnit.Case, async: false

  import Mox
  setup :set_mox_from_context
  setup :verify_on_exit!
  defmock(__MODULE__.Source, for: Packmatic.Source)

  test "works" do
    __MODULE__.Source
    |> expect(:validate, fn _ -> :ok end)
    |> expect(:init, &{:ok, %{__struct__: __MODULE__.Source, init_arg: &1}})
    |> expect(:read, fn _ -> ["foo"] end)
    |> expect(:read, fn _ -> ["bar"] end)
    |> expect(:read, fn _ -> ["baz"] end)
    |> expect(:read, fn _ -> :eof end)

    manifest_source_entry = {__MODULE__.Source, :erlang.unique_integer()}
    manifest = Packmatic.Manifest.create()
    manifest = Packmatic.Manifest.prepend(manifest, source: manifest_source_entry, path: "path")
    assert manifest.valid?

    {:ok, file_path} = Briefly.create(extname: ".zip")

    manifest
    |> Packmatic.build_stream()
    |> Stream.into(File.stream!(file_path, [:write]))
    |> Stream.run()

    assert {_, 0} = System.cmd("zipinfo", [file_path])
    assert {"foobarbaz", 0} = System.cmd("unzip", ["-p", file_path])
  end
end
