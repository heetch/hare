defmodule Hare.RPC.ClientTest do
  use ExUnit.Case, async: true

  alias Hare.Core.Conn
  alias Hare.RPC.Client

  defmodule TestClient do
    use Client

    def start_link(conn, config, pid),
      do: Client.start_link(__MODULE__, conn, config, pid)

    def request(client, payload),
      do: Client.request(client, payload)
    def request(client, payload, routing_key, opts),
      do: Client.request(client, payload, routing_key, opts)

    def handle_ready(meta, pid) do
      send(pid, {:ready, meta})
      {:noreply, pid}
    end

    def handle_request(payload, routing_key, opts, pid) do
      case Keyword.fetch(opts, :respond) do
        {:ok, "modify_request"}      -> {:ok, "foo - #{payload}", routing_key, [bar: "baz"], pid}
        {:ok, "reply: " <> response} -> {:reply, response, pid}
        {:ok, "stop: " <> response}  -> {:stop, "a_reason", response, pid}
        _otherwise                   -> {:ok, pid}
      end
    end

    def handle_info(message, pid) do
      send(pid, {:info, message})
      {:noreply, pid}
    end

    def terminate(reason, pid),
      do: send(pid, {:terminate, reason})
  end

  alias Hare.Adapter.Sandbox, as: Adapter

  def build_conn do
    {:ok, history} = Adapter.Backdoor.start_history
    {:ok, conn} = Conn.start_link(config:  [history: history],
                                  adapter: Adapter,
                                  backoff: [10])

    {history, conn}
  end

  test "echo server" do
    {history, conn} = build_conn

    config = [exchange: [name: "foo",
                         type: :fanout,
                         opts: [durable: true]]]

    {:ok, rpc_client} = TestClient.start_link(conn, config, self)

    send(rpc_client, {:consume_ok, %{bar: "baz"}})
    assert_receive {:ready, %{bar:          "baz",
                              resp_queue:   resp_queue,
                              req_exchange: req_exchange}}

    assert %{chan: chan,  name: resp_queue_name} = resp_queue
    assert %{chan: ^chan, name: "foo"} = req_exchange

    send(rpc_client, :some_message)
    assert_receive {:info, :some_message}

    payload     = "the request"
    routing_key = "the key"
    opts        = []

    request = Task.async fn ->
      TestClient.request(rpc_client, payload, routing_key, opts)
    end
    assert nil == Task.yield(request, 30)

    assert [{:open_channel,
              [_given_conn],
              {:ok, given_chan_1}},
            {:declare_server_named_queue,
              [given_chan_1, [auto_delete: true, exclusive: true]],
              {:ok, ^resp_queue_name, _info_2}},
            {:declare_exchange,
              [given_chan_1, "foo", :fanout, [durable: true]],
              :ok},
            {:consume,
              [given_chan_1, ^resp_queue_name, ^rpc_client, [no_ack: true]],
              {:ok, _consumer_tag}},
            {:monitor_channel,
              [given_chan_1],
              _ref},
            {:publish,
              [given_chan_1, "foo", ^payload, ^routing_key, opts],
              :ok}
           ] = Adapter.Backdoor.last_events(history, 6)

    assert resp_queue_name == Keyword.fetch!(opts, :reply_to)
    assert {:ok, correlation_id} = Keyword.fetch(opts, :correlation_id)

    response = "the response"
    meta     = %{correlation_id: correlation_id}
    send(rpc_client, {:deliver, response, meta})

    assert {:ok, response} == Task.await(request)
  end

  test "timeout" do
    {_history, conn} = build_conn

    config = [exchange: [name: "foo",
                         type: :fanout,
                         opts: [durable: true]],
              timeout: 1]

    {:ok, rpc_client} = TestClient.start_link(conn, config, self)

    payload = "the request"
    request = Task.async fn ->
      TestClient.request(rpc_client, payload)
    end

    Process.sleep(5)
    assert {:error, :timeout} == Task.await(request)
  end
end
