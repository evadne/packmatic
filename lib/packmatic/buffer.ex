defmodule Packmatic.Buffer do
  @moduledoc """
  The Buffer provides blocking writes and blocking reads to a pre-defined I/O buffer,
  which is suitable for applying backpressure to content loaded from servers.

  The Buffer is used by the URL source. It is implemented as a state machine with the
  following states:

  - Buffering: Where the buffer is in use. The Buffer is always in this state, but tracks
    the number of bytes already buffered. When it is not full, further calls to load data
    will return immediately; if the buffer is full, calls will not be handled until the
    buffer has been drained via the read call.
  - Finished: Where the buffer has been emptied and a call has marked the buffer as
    Finished, which is expected behaviour from the URL Source Reader. This is necessary so
    we can distinguish an interrupted connection from a correctly finished one.

  The use of the Buffer in the URL Source Reader is as follows:

  1. The URL Source Reader creates the Buffer, and continuously writes to it by making the
     `{:data, chunk}` calls, until it is blocked due to the buffer filling up, in which
     case further calls are postponed (blocked on caller side)

  2. The URL Source would read from the buffer whenever the Encoder calls `read/1`, which
     in time empties the buffer, allowing further `{:data, chunk}` calls to be unblocked

  3. The URL Source Reader would eventually, when the underlying Req request has finished
     properly, send a `:finish` call to the Buffer, which will cause the Buffer to return
     `:eof` when the URL Source eventually attempts to read from the Buffer. This is all
     properly sequenced, because all previous `{:data, chunk}` events will have to be
     processed first, before the `:finish` event can be processed.
  """

  defmodule Data do
    @moduledoc false
    defstruct buffer: :queue.new(), buffer_size_max: :infinity
  end

  @behaviour :gen_statem

  @impl :gen_statem
  def callback_mode do
    :handle_event_function
  end

  @impl :gen_statem
  def init(options) do
    with {:ok, buffer_size} <- Keyword.fetch(options, :buffer_size) do
      {:ok, {:buffering, 0}, %Data{buffer_size_max: buffer_size}}
    else
      :error -> {:error, "buffer_size should be specified in init_arg"}
    end
  end

  @impl :gen_statem
  def handle_event({:call, from}, {:data, chunk}, {:buffering, buffer_size}, data) do
    if buffer_size >= data.buffer_size_max do
      {:keep_state_and_data, :postpone}
    else
      buffer = :queue.in(chunk, data.buffer)
      buffer_size = buffer_size + :erlang.iolist_size(chunk)
      data = %{data | buffer: buffer}
      {:next_state, {:buffering, buffer_size}, data, {:reply, from, :ok}}
    end
  end

  @impl :gen_statem
  def handle_event({:call, from}, :finish, {:buffering, 0}, data) do
    {:next_state, :finished, data, {:reply, from, :ok}}
  end

  @impl :gen_statem
  def handle_event({:call, _from}, :finish, {:buffering, _}, _data) do
    {:keep_state_and_data, :postpone}
  end

  @impl :gen_statem
  def handle_event({:call, from}, :read, {:buffering, 0}, _data) do
    {:keep_state_and_data, {:reply, from, <<>>}}
  end

  @impl :gen_statem
  def handle_event({:call, from}, :read, {:buffering, _}, data) do
    buffer_iodata = :queue.to_list(data.buffer)
    data = %{data | buffer: :queue.new()}
    {:next_state, {:buffering, 0}, data, {:reply, from, buffer_iodata}}
  end

  @impl :gen_statem
  def handle_event({:call, from}, :read, :finished, _data) do
    {:keep_state_and_data, {:reply, from, :eof}}
  end

  if Mix.env() == :test do
    @impl :gen_statem
    def handle_event({:call, from}, :inspect, state, data) do
      {:keep_state_and_data, [{:reply, from, {:ok, state, data}}]}
    end
  end
end
