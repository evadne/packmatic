defmodule Packmatic.Source.URLTest do
  use ExUnit.Case, async: true
  doctest Packmatic.Source.URL

  test "can work independently" do
    module = Packmatic.Source.URL
  end

  test "reads one chunk at a time" do
    module = Packmatic.Source.URL
  end

  describe "when in a manifest" do
    setup do
      []
    end

    test "can work if used directly", context do
    end

    test "can work if used in dynamic source", context do
    end
  end
end
