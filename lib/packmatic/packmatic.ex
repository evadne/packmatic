defmodule Packmatic do
  @moduledoc """
  Top-level module holding the Packmatic library, which provides Zip-oriented stream aggregation
  services from various sources.
  """

  alias __MODULE__.Manifest
  alias __MODULE__.Encoder
  alias __MODULE__.StreamError

  @spec build_stream(manifest | manifest_entries, options) :: Enumerable.t()
        when manifest: Manifest.t(),
             manifest_entries: nonempty_list(Manifest.Entry.t() | Manifest.Entry.proplist()),
             options: [Encoder.option()]

  @doc """
  Builds a Stream which can be consumed to construct a Zip file from various sources, as specified
  in the Manifest. When building the Stream, options can be passed to configure how the Encoder
  should behave when Source acquisition fails.

  ## Examples

  The Stream can be created by passing a `t:Packmatic.Manifest.t/0` struct, a list of Manifest
  Entries (`t:Packmatic.Manifest.Entry.t/0`), or a list of Keyword Lists that are understood and
  can be transformed to Manifest Entries (`t:Packmatic.Manifest.Entry.proplist/0`).

      iex(1)> stream = Packmatic.build_stream(Packmatic.Manifest.create())
      iex(2)> is_function(stream)
      true

      iex(1)> stream = Packmatic.build_stream([])
      iex(2)> is_function(stream)
      true

      iex(1)> stream = Packmatic.build_stream([[source: {:file, "foo.bar"}]])
      iex(2)> is_function(stream)
      true
  """
  def build_stream(target, options \\ [])

  def build_stream(entries, options) when is_list(entries) do
    entries |> Manifest.create() |> build_stream(options)
  end

  def build_stream(%Manifest{} = manifest, options) do
    start_fun = fn ->
      case Encoder.stream_start(manifest, options) do
        {:ok, status, state} -> {status, state}
        {:error, reason} -> raise StreamError, reason: reason
      end
    end

    next_fun = fn {status, state} ->
      case Encoder.stream_next(status, state) do
        {:ok, :halt, status, state} -> {:halt, {status, state}}
        {:ok, data, status, state} -> {[data], {status, state}}
        {:error, reason} -> raise StreamError, reason: reason
      end
    end

    after_fun = fn {status, state} ->
      :ok = Encoder.stream_after(status, state)
    end

    Stream.resource(start_fun, next_fun, after_fun)
  end
end
