defmodule Packmatic.Manifest.Entry.Attributes do
  @moduledoc """
  The Manifest Entry Attributes represents the file’s UNIX and DOS attributes,
  such as UID, GID, sticky bit, UNIX permissions (`0o777` aka `rwxrwxrwx`, etc),
  in a way that is easy to specify.

  Terminology used in this module is inherited from the Linux `<sys/stat.h>` header
  and the capability of the module is designed to match what Erlang/OTP has in the
  `:file` module.
  """

  @type t :: %__MODULE__{
          mode: nil | mode,
          uid: nil | uid,
          gid: nil | gid,
          setuid: boolean(),
          setgid: boolean(),
          sticky: boolean()
        }

  @type proplist :: nonempty_list(mode | {:uid, uid} | {:gid, gid} | :setuid | :setgid | :sticky)
  
  @typedoc """
  Represents the representation of the Attributes within the Manifest Entry, which can either
  be the `t:mode/0` itself (as a shorthand) or a property list `t:proplist/0` that can be used to
  specify the file’s mode, any special bits, and the UID/GID of the file to be set upon decompression.
  """
  @type entry :: mode | proplist

  @typedoc """
  The short-hand UNIX mode of the entry; for example, `0o777` = `rwxrwxrwx`.
  See `:file.change_mode/2` for further information.
  """
  @type mode :: 0o000..0o777

  @type uid :: non_neg_integer()
  @type gid :: non_neg_integer()

  defstruct mode: 0o644, uid: nil, gid: nil, setuid: false, setgid: false, sticky: false

  defguardp is_mode(value) when is_integer(value) and 0o000 <= value and value <= 0o777

  def validate(entry) do
    case build(entry) do
      :error -> {:error, :invalid}
      _ -> :ok
    end
  end

  def build(nil) do
    %__MODULE__{}
  end

  def build(mode) when is_mode(mode) do
    build([mode])
  end

  def build(proplist) do
    Enum.reduce_while(proplist, %__MODULE__{}, fn
      {:uid, uid}, acc -> {:cont, %{acc | uid: uid}}
      {:gid, gid}, acc -> {:cont, %{acc | gid: gid}}
      :setuid, acc -> {:cont, %{acc | setuid: true}}
      :setgid, acc -> {:cont, %{acc | setgid: true}}
      :sticky, acc -> {:cont, %{acc | sticky: true}}
      mode, acc -> if is_mode(mode), do: {:cont, %{acc | mode: mode}}, else: {:halt, :error}
    end)
    |> case do
      %{uid: nil, gid: gid} when not is_nil(gid) -> :error
      %{uid: uid, gid: nil} when not is_nil(uid) -> :error
      x -> x
    end
  end
end
