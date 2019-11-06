defmodule Packmatic.Source do
  @moduledoc """
  Defines how data can be acquired in a piecemeal fashion, perhaps by reading only a few pages
  from the disk at a time or only a few MBs of data from an open socket.

  The Source behaviour defines two functions, `init/1` and `read/1`, that must be implemented by
  conforming modules. The first function initialises the Source and the second one iterates it,
  reading more data until there is no more.

  ## Representing Sources

  Sources are represented in Manifest Entries as tuples such as `{:file, path}` or `{:url, url}`.
  This form of representation is called a Source Entry; the first element in the tuple is the name
  and the second element is called the Initialisation Argument (`init_arg`).

  The Source Entry is a stable locator of the underlying data which has no runtime implications.
  The Encoder hydrates the Source Entry into whatever the Source module implements internally,
  when it is time to pull data from that source.

  The Initialisation Argument is usually a basic Elixir type, but in the case of Dynamic Sources,
  it is a function which resolves to a Source Entry understood by either the File or URL source.
  """

  @doc "Converts the Entry to a Source, or return failure."
  @callback init(term()) :: {:ok, struct()} | {:error, term()}

  @doc "Iterates the Source and return data as an IO List, `:eof`, or failure."
  @callback read(struct()) :: iodata() | :eof | {:error, term()}

  defmodule Builder do
    @moduledoc false

    def build_sources(source_names, module) do
      for source_name <- source_names do
        {:"#{String.downcase(source_name)}", Module.concat([module, source_name])}
      end
    end

    def build_quoted_entry_type(sources) do
      for {name, module} <- sources, reduce: [] do
        acc -> [quote(do: {unquote(name), unquote(module).init_arg()}) | acc]
      end
    end
  end

  source_names = ~w(File URL Random Dynamic)
  sources = Builder.build_sources(source_names, __MODULE__)

  @typedoc """
  Represents an internal tuple that can be used to initialise a Source with `build/1`. This allows
  the Entries to be dynamically resolved. Dynamic sources use this to prepare their work lazily,
  and other Sources may use this to open sockets or file handles.
  """
  @type entry :: unquote(Builder.build_quoted_entry_type(sources))

  @typedoc """
  Represents the internal (private) struct which holds runtime state for a resolved Source. In
  case of a File source, this may hold the File Handle indirectly; in case of a URL source this
  may indirectly refer to the underlying network socket.
  """
  @type t :: struct()

  for {name, module} <- sources do
    @spec build({unquote(name), unquote(module).init_arg()}) :: unquote(module).init_result()
  end

  @doc "Transforms an Entry into a Source ready for acquisition. Called by `Packmatic.Encoder`."
  for {name, module} <- sources do
    def build({unquote(name), init_arg}), do: unquote(module).init(init_arg)
  end

  @doc "Consumes bytes off an initialised Source. Called by `Packmatic.Encoder`."
  def read(%{__struct__: module} = source), do: module.read(source)
end
