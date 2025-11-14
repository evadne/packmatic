defmodule Packmatic.Compressor.Deflate do
  @moduledoc """
  Provides “DEFLATE” compression method for use in Zip archives, which compresses
  the incoming data stream.

  When specifying the Deflate compression method, the following values can be set
  in the initialisation argument:

  - `:level`, which corresponds to `t:zlib.zlevel()`; the default is `:default`.

  - `:strategy`, which corresponds to `t:zlib.zstrategy()`; the default is `:default`.
  """

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{zstream: :zlib.zstream()}
    @enforce_keys ~w(zstream)a
    defstruct zstream: nil
  end

  @behaviour Packmatic.Compressor

  @impl Packmatic.Compressor
  def open(init_arg) do
    # See Erlang/OTP source for :zip.put_z_file/10
    # See http://erlang.org/doc/man/zlib.html#deflateInit-1
    #
    # Quote:
    # > A negative WindowBits value suppresses the zlib header (and checksum)
    # > from the stream. Notice that the zlib source mentions this only as a
    # > undocumented feature.
    #
    # With the default WindowBits value of 15, deflate fails on macOS.

    zstream = :zlib.open()
    state = %State{zstream: zstream}
    level = Keyword.get(init_arg, :level, :default)
    strategy = Keyword.get(init_arg, :strategy, :default)
    :ok = :zlib.deflateInit(zstream, level, :deflated, -15, 8, strategy)
    {:ok, [], state}
  end

  @impl Packmatic.Compressor
  def next(data, state) do
    data = :zlib.deflate(state.zstream, data, :full)
    {:ok, data, state}
  end

  @impl Packmatic.Compressor
  def close(state) do
    data = :zlib.deflate(state.zstream, <<>>, :finish)
    {:ok, data, state}
  end

  @impl Packmatic.Compressor
  def reset(state, init_arg) do
    level = Keyword.get(init_arg, :level, :default)
    strategy = Keyword.get(init_arg, :strategy, :default)
    :ok = :zlib.deflateReset(state.zstream)
    :ok = :zlib.deflateParams(state.zstream, level, strategy)
    {:ok, [], state}
  end

  @impl Packmatic.Compressor
  def finalise(state) do
    :ok = :zlib.close(state.zstream)
  end
end
