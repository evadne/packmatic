defmodule Packmatic.Compressor.Deflate do
  @moduledoc """
  Provides “DEFLATE” compression method for use in Zip archives, which compresses
  the incoming data stream.
  """

  defmodule State do
    @type t :: %__MODULE__{
            zstream: :zlib.zstream()
          }

    @enforce_keys ~w(zstream)a
    defstruct zstream: nil
  end

  @behaviour Packmatic.Compressor

  @impl Packmatic.Compressor
  def open(_init_arg) do
    # See Erlang/OTP source for :zip.put_z_file/10
    # See http://erlang.org/doc/man/zlib.html#deflateInit-1
    #
    # Quote:
    # > A negative WindowBits value suppresses the zlib header (and checksum)
    # > from the stream. Notice that the zlib source mentions this only as a
    # > undocumented feature.
    #
    # With the default WindowBits value of 15, deflate fails on macOS.

    # TODO: handle actual zlib crash
    zstream = :zlib.open()
    state = %State{zstream: zstream}
    :ok = :zlib.deflateInit(zstream, :default, :deflated, -15, 8, :default)
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
  def reset(state, _init_arg) do
    # FIXME: use init_arg
    :ok = :zlib.deflateReset(state.zstream)
    {:ok, [], state}
  end
  
  @impl Packmatic.Compressor
  def finalise(state) do
    :ok = :zlib.close(state.zstream)
  end
end
