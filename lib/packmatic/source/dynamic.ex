defmodule Packmatic.Source.Dynamic do
  @moduledoc """
  Represents content which may be generated on-demand, for example by another subsystem or via
  downloading from a signed URL. The Dynamic source has no read function, and must initialise into
  a File or URL Source.
  """

  alias Packmatic.Source
  @type resolve_fun :: (() -> {:ok, Source.File.entry() | Source.URL.entry()})
  @type entry :: {:dynamic, resolve_fun}
  @type t :: Source.File.t() | Source.URL.t()
  @spec init(resolve_fun) :: t | {:error, atom()}

  def init(resolve_fun) do
    case resolve_fun.() do
      {:ok, {:file, path}} -> Source.File.init(path)
      {:ok, {:url, url}} -> Source.URL.init(url)
      {:error, reason} -> {:error, reason}
    end
  end
end
