defmodule Packmatic.Source do
  @moduledoc """
  Defines how data can be acquired in a piecemeal fashion, perhaps by reading only a few pages
  from the disk at a time or only a few MBs of data from an open socket.

  The Source behaviour defines three callbacks that must be implemented by conforming modules:

  1.  `c:validate/1`, which is called to check the initialisation argument.
  2.  `c:init/1`, which is called to instantiate the source and return its state.
  3.  `c:read/1`, which is called to read data from the source, given the state.

  ## Representing Sources

  Sources are represented in Manifest Entries as tuples such as `{:file, path}` or `{:url, url}`.
  This form of representation is called a Source Entry.

  The Source Entry is a stable locator of the underlying data which has no runtime implications.
  The Encoder hydrates the Source Entry into whatever the Source module implements internally,
  when it is time to pull data from that source.

  The first element in the tuple is the Source Name, and the second element is called the
  Initialisation Argument (`init_arg`).

  ### Source Name

  The Source names can be special atoms (short names) or full module names:

  1.  `:file` resolves to `Packmatic.Source.File`.
  2.  `:url` resolves to `Packmatic.Source.URL`.
  3.  `:dynamic` resolves to `Packmatic.Source.Dynamic`.
  4.  `:random` resolves to `Packmatic.Source.Random`.

  When using Custom Sources, the module name can be passed (as an atom) as well.

  ### Initialisation Argument

  The Initialisation Argument is usually a basic Elixir type, but in the case of Dynamic Sources,
  it is a function which resolves to a Source Entry understood by either the File or URL source.

  ### Examples

  The Source Entry `{:file, path}` is resolved during encoding:

      iex(1)> {:ok, file_path} = Briefly.create()
      iex(2)> {:ok, {module, state}} = Packmatic.Source.build({:file, file_path})
      iex(3)> module
      Packmatic.Source.File
      iex(3)> state.__struct__
      Packmatic.Source.File

  ### Notes

  When implementing a custom Source which uses an external data provider (for example reading from
  a file), remember to perform any cleanup required within the `read/1` callback if the Source is
  not expected to return any further data, for example if the file has been read completely or if
  there has been an error.
  """

  @typedoc """
  Represents the Name of the Source, which can be a shorthand (atom) or a module.
  """
  @type name :: atom() | module()

  @typedoc """
  Represents the Initialisation Argument which is a stable locator for the underlying data, that
  the Source will initialise based upon.
  """
  @type init_arg :: term()

  @typedoc """
  Represents the internal State for a resolved Source that is being read from.

  In case of a File source, the state may be a struct which holds the File Handle; in case of a
  URL source, it may be the underlying network socket, etc.
  """
  @type state :: term()

  @doc """
  Validates the given Initialisation Argument.
  """
  @callback validate(init_arg) :: :ok | {:error, term()}

  @doc """
  Converts the Entry to a Source State.
  """
  @callback init(term()) :: {:ok, state} | {:error, term()}

  @doc """
  Iterates the Source State.

  Usually this will return an IO List, or `{:error, reason}`. For stateful Sources, an updated
  Source State can be returned with the data. Note that Sources that have returned `:eof` or
  `{:error, reason}` will not be touched again.
  """
  @callback read(state) :: iodata() | {iodata(), state} | :eof | {:error, term()}

  @typedoc """
  Represents an internal tuple that can be used to initialise a Source with `build/1`.

  This allows the Entries to be dynamically resolved. Dynamic sources use this to prepare their
  work lazily, and other Sources may use this mechanism to delay opening of sockets or handles.
  """
  @type entry :: {name, init_arg}

  @typedoc false
  @opaque t :: {module(), state}

  @spec validate(entry) :: :ok | {:error, term()}
  @spec build(entry) :: {:ok, t} | {:error, term()}
  @spec read(t) :: iodata() | {iodata(), t} | :eof | {:error, term()}

  @doc """
  Validates the given Entry.

  Called by `Packmatic.Manifest.Entry`.
  """
  def validate(entry)

  def validate({name, init_arg}) do
    with {:module, module} <- resolve(name) do
      module.validate(init_arg)
    end
  end

  @doc """
  Initialises the Source with the Initialisation Argument as specified in the Entry. This prepares
  the Source for acquisition.

  Called by `Packmatic.Encoder`.
  """
  def build(entry)

  def build({name, init_arg}) do
    with {:module, module} <- resolve(name),
         {:ok, state} <- module.init(init_arg) do
      {:ok, {module, state}}
    end
  end

  @doc """
  Consumes bytes off an initialised Source.

  Called by `Packmatic.Encoder`.
  """
  def read(state)

  def read({module, state}) do
    case module.read(state) do
      {data, state} when is_binary(data) or is_list(data) -> {data, {module, state}}
      result -> result
    end
  end

  defp resolve(:file), do: {:module, __MODULE__.File}
  defp resolve(:url), do: {:module, __MODULE__.URL}
  defp resolve(:random), do: {:module, __MODULE__.Random}
  defp resolve(:dynamic), do: {:module, __MODULE__.Dynamic}
  defp resolve(:stream), do: {:module, __MODULE__.Stream}
  defp resolve(module) when is_atom(module), do: Code.ensure_loaded(module)
  defp resolve(_), do: {:error, :invalid_name}
end
