defmodule PackmaticTest.SocketProxy do
  @moduledoc """
  The Socket Proxy can be used to simulate closed connections, which is useful for testing
  scenarios that would otherwise propagate crashes (for example within Bypass handler).

  Within the Socket Proxy, a single acceptor is used. At any given time, the Socket Proxy can be
  told to halt, which will cause it to close the upstream and downstream sockets, without 
  reopening them, which simulates connection breakage.
  """

  @loopback {127, 0, 0, 1}

  @opaque t :: %__MODULE__{port: non_neg_integer(), pid: pid()}
  @enforce_keys ~w(port pid)a
  defstruct port: nil, pid: nil

  def start(options) do
    with {:ok, pid} <- __MODULE__.start_link(options),
         {:ok, port} <- GenServer.call(pid, :get_port) do
      {:ok, %__MODULE__{port: port, pid: pid}}
    end
  end

  def port(%__MODULE__{} = target) do
    target.port
  end

  def halt(%__MODULE__{} = target) do
    GenServer.call(target.pid, :halt)
  end

  use GenServer

  defmodule State do
    @type t :: %__MODULE__{
            upstream_port: non_neg_integer(),
            listen_socket: :gen_tcp.socket(),
            listen_port: non_neg_integer(),
            acceptor: nil | {pid(), reference()}
          }

    @enforce_keys ~w(upstream_port listen_socket listen_port acceptor)a
    defstruct upstream_port: nil, listen_socket: nil, listen_port: nil, acceptor: nil
  end

  def start_link(options) when is_list(options) do
    GenServer.start_link(__MODULE__, options)
  end

  def init(options) do
    with {:ok, upstream_port} <- Keyword.fetch(options, :port),
         {:ok, listen_socket} <- listen(),
         {:ok, listen_port} <- :inet.port(listen_socket),
         {:ok, acceptor} <- start_acceptor(listen_socket, upstream_port),
         state = %State{
           upstream_port: upstream_port,
           listen_socket: listen_socket,
           listen_port: listen_port,
           acceptor: acceptor
         } do
      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  def handle_call(:get_port, _, state) do
    {:reply, {:ok, state.listen_port}, state}
  end

  def handle_call(:halt, _, %{acceptor: {acceptor_pid, _}} = state) do
    _ = send(acceptor_pid, :halt)
    {:reply, :ok, %{state | acceptor: nil}}
  end

  def handle_call(:halt, _, %{acceptor: nil} = state) do
    {:reply, :ok, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _}, %{acceptor: {pid, ref}} = state) do
    with {:ok, acceptor} <- start_acceptor(state.listen_socket, state.upstream_port) do
      {:noreply, %{state | acceptor: acceptor}}
    end
  end

  def handle_info({:DOWN, _, :process, _, _}, %{acceptor: nil} = state) do
    {:noreply, state}
  end

  defp start_acceptor(listen_socket, upstream_port) do
    {:ok, spawn_monitor(__MODULE__, :accept, [listen_socket, upstream_port])}
  end

  defp listen do
    :gen_tcp.listen(0, [
      :binary,
      active: false,
      packet: :raw,
      nodelay: true,
      reuseaddr: true,
      backlog: 1024,
      ip: @loopback,
      send_timeout: 30000,
      send_timeout_close: true
    ])
  end

  def accept(listen_socket, upstream_port) do
    with {:ok, downstream_socket} <- accept_downstream(listen_socket),
         {:ok, upstream_socket} <- accept_upstream(upstream_port),
         :ok <- accept_empty_mailbox(),
         :ok <- :inet.setopts(downstream_socket, active: true) do
      accept_loop(upstream_socket, downstream_socket)
    else
      {:error, reason} -> Process.exit(self(), reason)
    end
  end

  defp accept_downstream(listen_socket) do
    :gen_tcp.accept(listen_socket)
  end

  defp accept_upstream(upstream_port) do
    options = [:binary, active: true, packet: :raw, nodelay: true]
    :gen_tcp.connect(@loopback, upstream_port, options)
  end

  defp accept_empty_mailbox do
    receive do
      _ -> accept_empty_mailbox()
    after
      0 -> :ok
    end
  end

  defp accept_loop(upstream_socket, downstream_socket) do
    receive do
      {:tcp, ^upstream_socket, data} ->
        :gen_tcp.send(downstream_socket, data)
        accept_loop(upstream_socket, downstream_socket)

      {:tcp, ^downstream_socket, data} ->
        :gen_tcp.send(upstream_socket, data)
        accept_loop(upstream_socket, downstream_socket)

      {:tcp_closed, ^upstream_socket} ->
        :gen_tcp.shutdown(downstream_socket, :read_write)

      {:tcp_closed, ^downstream_socket} ->
        :gen_tcp.shutdown(upstream_socket, :read_write)

      :halt ->
        :gen_tcp.shutdown(upstream_socket, :read_write)
        :gen_tcp.shutdown(downstream_socket, :read_write)
    end
  end
end
