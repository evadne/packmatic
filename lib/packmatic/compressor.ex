defmodule Packmatic.Compressor do
  @moduledoc """
  The Compressor is responsible for compressing source data for placement into the Zip archive.
  The Zip format supports different types of compression methods, so many different Compressors
  can be created, as long as they conform to the behaviour.
  """

  @typedoc "Represents a Compressor being used in the Encoder."
  @opaque t :: {module :: module(), init_arg :: term(), state :: term()}

  @type init_arg :: term()
  @type state :: term()
  @type data :: iodata()

  @doc """
  Initialises a Compressor with the initialisation argument specified in Entries. If
  such an argument was not specified then it should have been normalised to `[]`. The
  Compressor has the opportunity to emit the initial part of the data stream here.
  """
  @callback open(init_arg) :: {:ok, data, state} | {:error, reason :: term()}

  @doc """
  Iterates the Compressor with the incoming data, compresses it and emits both the compressed
  data, and if necessary, an updated state.
  """
  @callback next(state, data) :: {:ok, data, state} | {:error, reason :: term()}

  @doc """
  Closes down the Compressor at end of input stream. This is called when the input has been
  fully read (hit EOF) or further data is otherwise no longer expected for the input. When
  called, the Compressor may take the opportunity to emit a final part of the data stream,
  flushing its internal buffers. The Compressor is expected to then have emitted the entire
  data stream that can be used to reconstruct the input.

  After `c:close/1`, the Encoder may call `c:reset/2` again to compress a new input stream,
  or call `c:finalise/1` to close the Compressor down for good.
  """
  @callback close(state) :: {:ok, data, state} | {:error, reason :: term()}

  @doc """
  Closes the internal compression stream for the previous item and re-opens the Compressor for
  the next item. Functionally this would be identical to calling `close/1` and `open/1`, but in
  practice this callback is used to facilitate preservation of external resources that may
  be costly to open and close when compressing many items.
  """
  @callback reset(state, init_arg) :: {:ok, data, state} | {:error, reason :: term()}

  @doc """
  Closes the compressor for good. All external resources should be released here; no further calls 
  will be made by the Encoder past this point. Prior to this call, `c:close/1` should have been
  invoked to mark the end of a previous stream, so the Compressor is not expected to emit any
  further data.
  """
  @callback finalise(state) :: :ok | {:error, reason :: term()}

  @doc """
  Opens or resets the Compressor with the optional Initialisation Argument as specified in the Entry
  for a new file to be compressed.

  If the new Compression Method will result in the same Compressor being used again, then the existing
  Compressor will be reset (via `c:reset/2`); this may result in the existing Compressor being
  reused:

  1. If the new Compression Method requires a different Compressor, for example the method was
     `:store` but is then changed to `:deflate` for the subsequent entry, then the old Compressor will
     be closed and a new one will be opened in all scenarios.

  2. If the new Compression Method is resolved to the same Compressor, regardless of whether the
     Initialisation Argument is the same, `c:reset/2` will be called and it would be up to the
     relevant callback module to handle this.

  Called by `Packmatic.Encoder`.
  """

  @spec build(compressor :: t | nil, compression_method :: Packmatic.Manifest.Entry.method()) ::
          {:ok, data(), compressor :: t()} | {:error, reason :: term()}

  def build(compressor, compression_method) do
    with {:ok, module, init_arg} <- resolve(compression_method),
         {:ok, data, compressor} <- build_resolved(compressor, {module, init_arg}) do
      {:ok, data, compressor}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_resolved(nil, {module, init_arg}) do
    with {:ok, data, state} <- module.open(init_arg) do
      {:ok, data, {module, init_arg, state}}
    end
  end

  defp build_resolved({module, _init_arg, state}, {module, init_arg}) do
    with {:ok, data, state} <- module.reset(state, init_arg) do
      {:ok, data, {module, init_arg, state}}
    end
  end

  defp build_resolved({old_module, _old_init_arg, old_state}, {new_module, new_init_arg}) do
    with :ok <- old_module.finalise(old_state),
         {:ok, data, state} <- new_module.open(new_init_arg) do
      {:ok, data, {new_module, new_init_arg, state}}
    end
  end

  def next({module, init_arg, state}, data) do
    case module.next(data, state) do
      {:ok, data, state} -> {:ok, data, {module, init_arg, state}}
      {:error, reason} -> {:error, reason}
    end
  end

  def close({module, init_arg, state}) do
    case module.close(state) do
      {:ok, data, state} -> {:ok, data, {module, init_arg, state}}
      {:error, reason} -> {:error, reason}
    end
  end

  def reset({module, init_arg, state}) do
    case module.reset(state) do
      {:ok, data, state} -> {:ok, data, {module, init_arg, state}}
      {:error, reason} -> {:error, reason}
    end
  end

  def finalise({module, _init_arg, state}) do
    case module.finalise(state) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve(compression_method)
  defp resolve(:store), do: {:ok, __MODULE__.Store, []}
  defp resolve(:deflate), do: {:ok, __MODULE__.Deflate, []}
  defp resolve({:deflate, options}), do: {:ok, __MODULE__.Deflate, options}
  defp resolve(_), do: :error
end
