defmodule Packmatic do
  @moduledoc """
  Top-level module holding the Packmatic library, which provides ZIP-oriented stream aggregation
  services from various sources.
  """

  alias __MODULE__.Manifest
  alias __MODULE__.Encoder

  @type manifest :: Manifest.t()
  @type options :: Encoder.options()
  @type source_entry :: Packmatic.Source.entry()
  @type source_path :: Path.t()
  @type source_option :: {:timestamp, DateTime.t()}
  @type stream_entry :: {source_entry, source_path}
  @type stream_entry_extended :: {source_entry, source_path, nonempty_list(source_option)}
  @spec build_stream(manifest, options) :: term()
  @spec build_stream(nonempty_list(stream_entry | stream_entry_extended), options) :: term()

  @doc """
  Builds a Stream which can be consumed to construct a ZIP file from various sources, as specified
  in the Manifest. When buinding the Stream, options can be passed to configure how the Encoder
  should behave when Source acquisition fails.

  ## Examples

      stream = Packmatic.build_stream([
        {{:file, "/tmp/hello.pdf"}, "hello.pdf"},
        {{:file, "/tmp/world.pdf"}, "world.pdf"}
      ])

      stream = Packmatic.build_stream([
        {{:file, "/tmp/htllo.pdf"}, "hello.pdf"},
        {{:file, "/tmp/world.pdf"}, "world.pdf"}
      ], on_error: :skip)
  """

  def build_stream(target, options \\ [])

  def build_stream(entries, options) when is_list(entries) do
    entries
    |> Enum.reduce(Manifest.create(), &build_stream_prepend/2)
    |> build_stream(options)
  end

  def build_stream(%Manifest{} = manifest, options) do
    start_fun = fn ->
      case __MODULE__.Encoder.stream_start(manifest, options) do
        {:ok, status, state} -> {status, state}
        {:error, reason} -> raise __MODULE__.StreamError, reason: reason
      end
    end

    next_fun = fn {status, state} ->
      case __MODULE__.Encoder.stream_next(status, state) do
        {:ok, :halt, status, state} -> {:halt, {status, state}}
        {:ok, list, status, state} when is_list(list) -> {list, {status, state}}
        {:error, reason} -> raise __MODULE__.StreamError, reason: reason
      end
    end

    after_fun = fn {status, state} ->
      :ok = __MODULE__.Encoder.stream_after(status, state)
    end

    Stream.resource(start_fun, next_fun, after_fun)
  end

  defp build_stream_prepend({source, path}, manifest) do
    Manifest.prepend(manifest, source: source, path: path)
  end

  defp build_stream_prepend({source, path, options}, manifest) do
    keyword = Keyword.merge(Keyword.take(options, ~w(timestamp)a), source: source, path: path)
    Manifest.prepend(manifest, keyword)
  end
end
