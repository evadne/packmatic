defmodule Packmatic.ManifestTest do
  use ExUnit.Case, async: true
  alias Packmatic.Manifest
  doctest Packmatic.Manifest

  describe "create/0" do
    test "returns invalid empty model" do
      assert %Manifest{valid?: false} = Manifest.create()
    end
  end

  describe "create/1" do
    test "returns invalid empty model if given empty list" do
      assert %{valid?: false} = Manifest.create([])
    end

    test "returns valid model if given list with valid Entry model" do
      source = {:file, "/tmp/example.com"}
      path = "example.pdf"
      timestamp = DateTime.utc_now()
      entry = %Manifest.Entry{source: source, path: path, timestamp: timestamp}
      assert %{valid?: true} = Manifest.create([entry])
    end

    test "returns valid model if given list with valid Entry keyword" do
      entry = [source: {:file, "x"}, path: "example.pdf"]
      assert %{valid?: true} = Manifest.create([entry])
    end
  end

  describe "errors" do
    test "preserve order of entries" do
      entries = [
        [path: "example.pdf"],
        [source: {:file, "foo.pdf"}, timestamp: DateTime.utc_now()]
      ]

      assert %{valid?: false, errors: errors} = Manifest.create(entries)
      assert {{:entry, -2}, [source: :missing]} = List.keyfind(errors, {:entry, -2}, 0)
      assert {{:entry, -1}, [path: :missing]} = List.keyfind(errors, {:entry, -1}, 0)
    end
  end
end
