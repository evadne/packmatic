defmodule Packmatic.Compressor do
  @moduledoc """
  The Compressor module is responsible for compressing source data for placement into 
  the Zip archive. Further Compressors should comply to the behaviour in this module.
  """

  @typedoc "Represents a Compressor being used in the Encoder"
  @type t :: {module :: module(), init_arg :: term(), state :: term()}

  @type init_arg :: term()
  @type state :: term()
  @type reason :: term()
  @type data :: iodata()

  @doc """
  Initialises a Compressor with the initialisation argument specified in Entries. If
  such an argument was not specified then it should have been normalised to `[]`. The
  Compressor has the opportunity to emit the initial part of the data stream here.
  """
  @callback open(init_arg) :: {:ok, data, state} | {:error, reason}

  @doc """
  Iterates the Compressor with the incoming data, compresses it and emits both the
  compressed data and an updated state.
  """
  @callback next(state, data) :: {:ok, data, state} | {:error, reason}

  @doc """
  Finalises the Compressor for end of input stream. The Compressor may take the opportunity
  to emit a final part of the data stream which closes the compressed stream, however, no
  further calls are expected from the Encoder so all cleanup should be done here.
  """
  @callback close(state) :: {:ok, data, state} | {:error, reason}

  @doc """
  Closes the internal compression stream for the previous item and re-opens the Compressor for
  the next item. Functionally this would be identical to calling `close/1` and `open/1`, but in
  practice this callback is used to facilitate preservation of external resources that may
  be costly to open and close when compressing many items.
  """
  @callback reset(state, init_arg) :: {:ok, data, state} | {:error, reason}

  @doc """
  Closes the compressor for good. All external resources should be released here; no further calls 
  will be made by the Encoder past this point. Prior to this call, close/1 should have been invoked
  to mark the end of a previous stream.
  """
  @callback finalise(state) :: :ok | {:error, reason}

  @doc """
  Opens or resets the Compressor with the optional Initialisation Argument as specified in the Entry
  for a new file to be compressed.

  If the new Compression Method will result in the same Compressor being used again, then the existing
  Compressor will be reset (via `callback: reset/1`); this may result in the existing Compressor being
  reused. If the new Compression Method requires a different Compressor, for example the method was
  `:store` but is then changed to `:deflate` for the subsequent entry, then the old Compressor will
  be closed and a new one will be opened in all scenarios.

  Called by `Packmatic.Encoder`.
  """
  
  @spec build(compressor :: t | nil, compression_method :: Packmatic.Manifest.Entry.method()) :: 
    {:ok, data(), compressor :: t()} | {:error, reason()}

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
  defp resolve({:deflate, level}), do: {:ok, __MODULE__.Deflate, [level: level]}
  defp resolve(_), do: :error
end
