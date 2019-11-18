defmodule Packmatic.Manifest do
  @moduledoc """
  Represents the customer’s request for a particular compressed file.

  The Manifest is constructed with a list of `Packmatic.Manifest.Entry` structs, which each
  represents one file to be placed into the Package. Entries are validated when they are added to
  the Manifest.

  ## Creating Manifests

  Manifests can be created iteratively by calling `prepend/2` against an existing Manifest, or by
  calling `create/1` with a list of Entries created elsewhere.

  Calling `create/0` provides you with an empty Manifest which is not valid:

      iex(1)> Packmatic.Manifest.create()
      %Packmatic.Manifest{entries: [], errors: [manifest: :empty], valid?: false}

  However, prepending valid Entries makes it valid:

      iex(1)> manifest = Packmatic.Manifest.create()
      iex(2)> manifest = Packmatic.Manifest.prepend(manifest, source: {:random, 1}, path: "foo")
      iex(3)> manifest.valid?
      true

  Creating a Manifest from a list of Entries also results in a valid Manifest:

      iex(1)> manifest = Packmatic.Manifest.create([[source: {:random, 1}, path: "foo"]])
      iex(2)> manifest.valid?
      true

  ## Validity and Error Reporting

  An empty Manifest is not valid because the result is not useful. It contains a Manifest-level
  error `{:manifest, :empty}`.

      iex(1)> manifest = Packmatic.Manifest.create()
      iex(2)> manifest.errors
      [manifest: :empty]

  If an Entry is not valid when appended to a Manifest, it will make the Manifest invalid and a
  corresponding error entry will also be added to the `:errors` key.

  Since entries are prepended to the list, Entry-level errors are emitted with a negative index
  (counted from the tail of the list). So the last item (first to be appended) has the index of
  `-1`, the penultimate item has the index of `-2`, and so on.

      iex(1)> manifest = Packmatic.Manifest.create()
      iex(2)> manifest = Packmatic.Manifest.prepend(manifest, source: {:file, nil})
      iex(3)> manifest.errors
      [{{:entry, -1}, [source: :invalid, path: :missing]}]

  Entry-level errors are emitted per key, and defined under `t:Packmatic.Manifest.Entry.error/0`.
  """

  alias __MODULE__.Entry

  entries = quote do: nonempty_list(Entry.t())
  errors = quote do: nonempty_list(error)

  @typedoc "Represents the Manifest."
  @type t :: %__MODULE__{entries: [Entry.t()], errors: [error], valid?: true | false}

  @typedoc "Represents a valid Manifest, where there must be Entries and no errors."
  @type valid :: %__MODULE__{entries: unquote(entries), errors: [], valid?: true}

  @typedoc "Represents an invalid Manifest, where there must be errors and might be Entries."
  @type invalid :: %__MODULE__{entries: list(Entry.t()), errors: unquote(errors), valid?: false}

  @typedoc "Represents an Error which can be related to an Entry or the Manifest itself."
  @type error :: error_entry | error_manifest

  @typedoc "Represents an Error regarding an Entry. Index is negative, counted from tail."
  @type error_entry :: {{:entry, neg_integer()}, Entry.error()}

  @typedoc "Represents an Error with the Manifest."
  @type error_manifest :: {:manifest, error_manifest_reason}

  @typedoc "Represents an error condition where the Manifest has no entries."
  @type error_manifest_reason :: :empty

  @enforce_keys ~w(entries)a
  defstruct entries: [], errors: [], valid?: false

  @spec create() :: invalid()
  @spec create([]) :: invalid()
  @spec create(nonempty_list(Entry.t() | Entry.proplist())) :: valid() | invalid()
  @spec prepend(t(), Entry.t() | Entry.proplist()) :: valid() | invalid()

  @doc """
  Creates a Manifest based on Entries given. If there are no Entries, the Manifest will be
  invalid by default. Otherwise, each Entry will be validated and the Manifest will remain valid
  if all Entries provided were valid.
  """
  def create(entries \\ [])

  def create([]) do
    %__MODULE__{entries: [], errors: [{:manifest, :empty}], valid?: false}
  end

  def create(entries) when is_list(entries) do
    for entry <- Enum.reverse(entries), reduce: %__MODULE__{entries: [], valid?: true} do
      model -> prepend(model, entry)
    end
  end

  @doc """
  Prepends the given Entry to the Manifest. If the Entry is invalid, the Manifest will also
  become invalid, and the error will be prepended to the list.
  """
  def prepend(model, target)

  def prepend(%{entries: [], errors: [_ | _], valid?: false} = model, target) do
    prepend(%{model | errors: [], valid?: true}, target)
  end

  def prepend(model, %Entry{} = entry) do
    case Packmatic.Validator.validate(entry) do
      :ok -> prepend_entry_valid(model, entry)
      {:error, errors} -> prepend_entry_invalid(model, entry, errors)
    end
  end

  def prepend(model, keyword) when is_list(keyword) do
    prepend(model, struct(Entry, keyword))
  end

  defp prepend_entry_valid(model, entry) do
    %{model | entries: [entry | model.entries]}
  end

  defp prepend_entry_invalid(model, entry, errors) do
    error = {{:entry, -1 * (1 + length(model.entries))}, errors}
    %{model | entries: [entry | model.entries], errors: [error | model.errors], valid?: false}
  end
end
