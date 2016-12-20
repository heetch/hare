defmodule Hare.Core.Conn do
  use Connection

  alias __MODULE__.State

  def start_link(config, opts \\ []),
    do: Connection.start_link(__MODULE__, config, opts)

  def open_channel(conn),
    do: Connection.call(conn, :open_channel)

  def given_conn(conn),
    do: Connection.call(conn, :given_conn)

  def stop(conn, reason \\ :normal),
    do: Connection.call(conn, {:close, reason})

  def init(config) do
    state = State.new(config, &Connection.reply/2)

    {:connect, :init, state}
  end

  def connect(_info, state) do
    case State.connect(state) do
      {:ok, new_state}              -> {:ok, new_state}
      {:retry, interval, new_state} -> {:backoff, interval, new_state}
    end
  end

  def disconnect(reason, state),
    do: {:stop, reason, state}

  def handle_call(:open_channel, from, state) do
    case State.open_channel(state, from) do
      {:wait, new_state} -> {:noreply, new_state}
      result             -> {:reply, result, state}
    end
  end
  def handle_call({:close, reason}, _from, state) do
    {:disconnect, reason, :ok, state}
  end
  def handle_call(:given_conn, _from, state) do
    {:reply, State.given_conn(state), state}
  end

  def handle_info({:DOWN, ref, _, _, _reason}, state) do
    case State.down?(state, ref) do
      true  -> {:connect, :reconnect, state}
      false -> {:noreply, state}
    end
  end
  def handle_info(_anything, state) do
    {:noreply, state}
  end

  def terminate(_reason, state),
    do: State.disconnect(state)
end
