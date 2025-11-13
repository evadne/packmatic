defmodule Packmatic.BufferTest do
  use ExUnit.Case, async: true
  alias Packmatic.Buffer

  test "works" do
    {:ok, buffer_pid} = :gen_statem.start_link(Buffer, [buffer_size: 1_048_576], [])
    chunk = :crypto.strong_rand_bytes(1024)
    assert :ok = :gen_statem.call(buffer_pid, {:data, chunk})
    assert ^chunk = IO.iodata_to_binary(:gen_statem.call(buffer_pid, :read))
    assert <<>> = :gen_statem.call(buffer_pid, :read)
    assert :ok = :gen_statem.call(buffer_pid, :finish)
    assert :eof = :gen_statem.call(buffer_pid, :read)
  end

  test "drain/1 works immediately" do
    {:ok, buffer_pid} = :gen_statem.start_link(Buffer, [buffer_size: 16], [])
    assert <<>> = :gen_statem.call(buffer_pid, :read)
  end

  test "data/2 blocks if limit is exceeded" do
    {:ok, buffer_pid} = :gen_statem.start_link(Buffer, [buffer_size: 16], [])
    chunk = :crypto.strong_rand_bytes(32)
    assert :ok = :gen_statem.call(buffer_pid, {:data, chunk})
    parent_pid = self()

    spawn(fn ->
      assert :ok = :gen_statem.call(buffer_pid, {:data, chunk})
      send(parent_pid, :appended)
    end)

    refute_receive :appended
    assert ^chunk = IO.iodata_to_binary(:gen_statem.call(buffer_pid, :read))

    assert_receive :appended
    assert ^chunk = IO.iodata_to_binary(:gen_statem.call(buffer_pid, :read))

    {:ok, state, data} = :gen_statem.call(buffer_pid, :inspect)
    assert {:buffering, 0} = state
    assert %{buffer: {[], []}} = data
  end
end
