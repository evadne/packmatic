defmodule Packmatic.SourceTest do
  use ExUnit.Case, async: true
  doctest Packmatic.Source

  import Mox
  setup :set_mox_from_context
  setup :verify_on_exit!
  defmock(__MODULE__.Source, for: Packmatic.Source)

  describe "build/1" do
    test "resolves :file" do
      {:ok, file_path} = Briefly.create()
      {:ok, {module, state}} = Packmatic.Source.build({:file, file_path})
      assert Packmatic.Source.File = module
      assert %Packmatic.Source.File{} = state
    end

    test "resolves Packmatic.Source.File" do
      {:ok, file_path} = Briefly.create()
      {:ok, {module, state}} = Packmatic.Source.build({Packmatic.Source.File, file_path})
      assert Packmatic.Source.File = module
      assert %Packmatic.Source.File{} = state
    end

    test "resolves custom source" do
      init_arg = :erlang.unique_integer()
      state = %{__struct__: __MODULE__.Source, init_arg: init_arg}
      expect(__MODULE__.Source, :init, fn ^init_arg -> {:ok, state} end)
      assert {:ok, {module, state}} = Packmatic.Source.build({__MODULE__.Source, init_arg})
      assert __MODULE__.Source = module
      assert %{__struct__: __MODULE__.Source, init_arg: ^init_arg} = state
    end

    test "rejects unknown source" do
      assert {:error, _} = Packmatic.Source.build({:foo, nil})
    end
  end
end
