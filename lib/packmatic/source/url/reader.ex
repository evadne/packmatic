defmodule Packmatic.Source.URL.Reader do
  @moduledoc false
  alias Packmatic.Buffer

  defmodule Data do
    @moduledoc false
    defstruct buffer_pid: nil, task_pid: nil
  end

  @buffer_options [buffer_size: 1_048_576]

  @behaviour :gen_statem

  @impl :gen_statem
  def callback_mode do
    :handle_event_function
  end

  @impl :gen_statem
  def init({target, options}) do
    request = Req.new(Keyword.merge([url: to_string(target), method: :get], options))
    buffer_options = Keyword.get(options, :buffer_options, [])
    buffer_options = Keyword.merge(@buffer_options, buffer_options)
    parent_pid = self()
    {:ok, buffer_pid} = :gen_statem.start_link(Buffer, buffer_options, [])
    {:ok, task_pid} = Task.start_link(fn -> task_fun(request, buffer_pid, parent_pid) end)
    data = %Data{buffer_pid: buffer_pid, task_pid: task_pid}
    {:ok, :connecting, data}
  end

  @impl :gen_statem
  def handle_event({:call, _from}, :connect, :connecting, _data) do
    {:keep_state_and_data, :postpone}
  end

  @impl :gen_statem
  def handle_event({:call, from}, :connect, :connected, _data) do
    {:keep_state_and_data, {:reply, from, :ok}}
  end

  @impl :gen_statem
  def handle_event({:call, from}, :connect, {:error, reason}, _data) do
    {:keep_state_and_data, {:reply, from, {:error, reason}}}
  end

  @impl :gen_statem
  def handle_event({:call, from}, {:connected, response}, :connecting, data) do
    case response do
      %{status: 200} -> {:next_state, :connected, data, {:reply, from, :ok}}
      _ -> {:next_state, {:error, response}, data, {:reply, from, :ok}}
    end
  end

  @impl :gen_statem
  def handle_event({:call, _from}, :read, :connecting, _data) do
    {:keep_state_and_data, :postpone}
  end

  @impl :gen_statem
  def handle_event({:call, from}, :read, :connected, data) do
    {:keep_state_and_data, {:reply, from, {:ok, data.buffer_pid}}}
  end

  @impl :gen_statem
  def handle_event({:call, from}, :read, {:error, reason}, _data) do
    {:keep_state_and_data, {:reply, from, {:error, reason}}}
  end

  @impl :gen_statem
  def handle_event(:cast, {:request_finished, result}, :connected, data) do
    case result do
      {:ok, _} -> :keep_state_and_data
      {:error, reason} -> {:next_state, {:error, reason}, data}
    end
  end

  @impl :gen_statem
  def handle_event(:cast, {:request_finished, _}, {:error, _}, _data) do
    :keep_state_and_data
  end

  defp task_fun(request, buffer_pid, parent_pid) do
    into_fun = fn {:data, data}, {request, response} = acc ->
      case response do
        %Req.Response{status: 200, private: %{connected: true}} ->
          :ok = :gen_statem.call(buffer_pid, {:data, data})
          {:cont, acc}

        %Req.Response{status: 200} ->
          :ok = :gen_statem.call(buffer_pid, {:data, data})
          :ok = :gen_statem.call(parent_pid, {:connected, response})
          response = Req.Response.put_private(response, :connected, true)
          {:cont, {request, response}}

        %Req.Response{} ->
          :ok = :gen_statem.call(parent_pid, {:connected, response})
          response = Req.Response.put_private(response, :connected, true)
          {:halt, {request, response}}
      end
    end

    result = Req.request(request, into: into_fun, raw: true)

    with {:ok, %{status: 200}} <- result do
      :ok = :gen_statem.call(buffer_pid, :finish)
    end

    :gen_statem.cast(parent_pid, {:request_finished, result})
  end
end
