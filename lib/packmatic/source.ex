defmodule Packmatic.Source do
  @moduledoc """
  Defines how data can be acquired in a piecemeal fashion, perhaps by reading only a few pages
  from the disk at a time or only a few MBs of data from an open socket.
  """

  @type entry_file :: __MODULE__.File.entry()
  @type entry_url :: __MODULE__.URL.entry()
  @type entry_random :: __MODULE__.Random.entry()
  @type entry_dynamic :: __MODULE__.Dynamic.entry()
  @type entry :: entry_file | entry_url | entry_random | entry_dynamic

  @spec build(entry_file) :: {:ok, __MODULE__.File.t()} | {:error, term()}
  @spec build(entry_url) :: {:ok, __MODULE__.URL.t()} | {:error, term()}
  @spec build(entry_random) :: {:ok, __MODULE__.Random.t()} | {:error, term()}
  @spec build(entry_dynamic) :: {:ok, __MODULE__.Dynamic.t()} | {:error, term()}

  @doc "Converts the Entry to a Source, or return failure."
  @callback init(term()) :: {:ok, struct()} | {:error, term()}

  @doc "Iterates the Source and return data as an IO List, `:eof`, or failure."
  @callback read(struct()) :: iodata() | :eof | {:error, term()}

  @doc "Transforms an Entry into a Source ready for acquisition. Called by `Packmatic.Encoder`."
  def build({:file, path}), do: __MODULE__.File.init(path)
  def build({:url, url}), do: __MODULE__.URL.init(url)
  def build({:random, size}), do: __MODULE__.Random.init(size)
  def build({:dynamic, resolve_fun}), do: __MODULE__.Dynamic.init(resolve_fun)

  @doc "Consumes bytes off an initialised Source. Called by `Packmatic.Encoder`."
  def read(%{__struct__: module} = source), do: module.read(source)
end
