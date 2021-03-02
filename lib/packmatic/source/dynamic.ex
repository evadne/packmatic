defmodule Packmatic.Source.Dynamic do
  @moduledoc """
  Represents content which may be generated on-demand, for example by another subsystem or via
  downloading from a signed URL.

  For example, a function which dynamically generates a URL (perhaps a signed S3 URL in your own
  use case) would look like this:

      iex(1)> url = "https://example.com"
      iex(2)> init_arg = fn -> {:ok, {:url, url}} end
      iex(3)> {:ok, {module, source}} = Packmatic.Source.Dynamic.init(init_arg)
      iex(4)> module
      Packmatic.Source.URL
      iex(5)> source.__struct__
      Packmatic.Source.URL

  And when used within a Manifest, it would look like this:

      iex(1)> url = "https://example.com"
      iex(2)> init_arg = fn -> {:ok, {:url, url}} end
      iex(3)> entry = [source: {:dynamic, init_arg}, path: "foo.pdf"]
      iex(4)> manifest = Packmatic.Manifest.create([entry])
      iex(5)> manifest.valid?
      true

  Even if the function (referenced by the Initialisation Argument) resolves cleanly, the result
  may still be rejected by the underlying Source, for example if the file does not exist. This
  kind of error “bubbles up” and is dealt with by the Encoder at runtime.

      iex(1)> Packmatic.Source.Dynamic.init(fn -> {:ok, {:file, "example.pdf"}} end)
      {:error, :enoent}

  However, since resolution happens only when the built Stream starts to be consumed, such a
  Source Entry would be valid when placed in a Manifest ahead of time:

      iex(1)> path = "example.pdf"
      iex(2)> init_arg = fn -> {:ok, {:file, path}} end
      iex(3)> entry = [source: {:dynamic, init_arg}, path: "foo.pdf"]
      iex(4)> manifest = Packmatic.Manifest.create([entry])
      iex(5)> manifest.valid?
      true
  """

  alias Packmatic.Source
  @behaviour Source

  @type init_arg :: resolve_fun
  @type init_result :: {:ok, Source.state()} | {:error, term()}
  @spec init(init_arg) :: init_result

  @type resolve_fun :: (() -> resolve_result | resolve_result_error)
  @type resolve_result :: {:ok, Source.entry()}
  @type resolve_result_error :: {:error, term()}

  @impl Source
  def validate(fun) when is_function(fun, 0), do: :ok
  def validate(_), do: {:error, :invalid}

  @impl Source
  def init(resolve_fun) do
    case resolve_fun.() do
      {:ok, entry} -> Source.build(entry)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Source
  def read({module, state}) do
    case module.read(state) do
      {data, state} when is_binary(data) or is_list(data) -> {data, {module, state}}
      result -> result
    end
  end
end
