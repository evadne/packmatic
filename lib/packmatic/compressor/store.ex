defmodule Packmatic.Compressor.Store do
  @moduledoc """
  Provides “STORE” compression method for use in Zip archives. The “STORE” method does not
  actually compress the incoming data stream.
  """

  @behaviour Packmatic.Compressor

  @impl Packmatic.Compressor
  def open(_init_arg) do
    {:ok, [], nil}
  end

  @impl Packmatic.Compressor
  def next(data, state) do
    {:ok, data, state}
  end

  @impl Packmatic.Compressor
  def close(state) do
    {:ok, [], state}
  end

  @impl Packmatic.Compressor
  def reset(state, _init_arg) do
    {:ok, [], state}
  end

  @impl Packmatic.Compressor
  def finalise(_state) do
    :ok
  end
end
