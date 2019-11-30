defmodule Packmatic.Source.Random do
  @moduledoc """
  Represents randomly generated content, which is used mostly for testing, when you want to have a
  particular entry generated to a specific length.
  """

  alias Packmatic.Source
  @behaviour Source

  @type init_arg :: non_neg_integer
  @type init_result :: {:ok, t}
  @spec init(init_arg) :: init_result

  @type t :: %__MODULE__{agent_pid: pid()}
  @enforce_keys ~w(agent_pid)a
  defstruct agent_pid: nil

  @impl Source
  def validate(bytes) when is_number(bytes) and bytes > 0, do: :ok
  def validate(_), do: {:error, :invalid}

  @impl Source
  def init(bytes_remaining) do
    agent_fun = fn ->
      state = %__MODULE__.State{bytes_remaining: bytes_remaining}
      template = :crypto.strong_rand_bytes(state.chunk_size)
      {state, template}
    end

    {:ok, pid} = Agent.start_link(agent_fun)
    {:ok, %__MODULE__{agent_pid: pid}}
  end

  @impl Source
  def read(%__MODULE__{} = source) do
    get_and_update_fun = fn {state, template} ->
      bytes = min(state.bytes_remaining, state.chunk_size)
      result = :binary.part(template, 0, bytes)
      state = %{state | bytes_remaining: state.bytes_remaining - bytes}
      {result, {state, template}}
    end

    with <<>> <- Agent.get_and_update(source.agent_pid, get_and_update_fun) do
      :ok = Agent.stop(source.agent_pid)
      :eof
    else
      result -> result
    end
  end
end
