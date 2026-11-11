defmodule GossipNode.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: GossipNode.PeerRegistry},
      {GossipNode.Mempool, []},
      {GossipNode.GossipServer, []},
      {GossipNode.PeerDiscovery, []},
      {GossipNode.PeerConnectionManager, []}
    ]

    opts = [strategy: :one_for_one, name: GossipNode.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule GossipNode.Mempool do
  use GenServer

  # Public API
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %MapSet{}, name: __MODULE__)
  end

  def submit_tx(tx) do
    GenServer.call(__MODULE__, {:submit_tx, tx})
  end

  def get_txs do
    GenServer.call(__MODULE__, :get_txs)
  end

  # Callbacks
  def init(state) do
    {:ok, state}
  end

  def handle_call({:submit_tx, tx}, _from, state) do
    hash = tx_hash(tx)
    if MapSet.member?(state, hash) do
      {:reply, {:error, :duplicate}, state}
    else
      new_state = MapSet.put(state, hash)
      # Notify gossip server about the new transaction
      GossipNode.GossipServer.new_tx(hash, tx)
      {:reply, {:ok, hash}, new_state}
    end
  end

  def handle_call(:get_txs, _from, state) do
    {:reply, MapSet.to_list(state), state}
  end

  def handle_cast({:receive_tx, hash, tx}, state) do
    if MapSet.member?(state, hash) do
      {:noreply, state}
    else
      new_state = MapSet.put(state, hash)
      # Propagate further to the network
      GossipNode.GossipServer.new_tx(hash, tx)
      {:noreply, new_state}
    end
  end

  defp tx_hash(tx) do
    :crypto.hash(:sha256, :erlang.term_to_binary(tx))
    |> Base.encode16()
  end
end

defmodule GossipNode.PeerRegistry do
  @moduledoc false

  # Register the calling process as a peer
  def add_peer(pid) when is_pid(pid) do
    Registry.register(GossipNode.PeerRegistry, pid, %{})
  end

  # Return a list of all registered peer pids
  def list_peers do
    Registry.select(GossipNode.PeerRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  # Remove a peer from the registry
  def remove_peer(pid) when is_pid(pid) do
    Registry.delete(GossipNode.PeerRegistry, pid)
  end
end

defmodule GossipNode.GossipServer do
  use GenServer

  @gossip_interval 5_000 # milliseconds

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Public API to inform the server about a newly seen transaction
  def new_tx(hash, tx) do
    GenServer.cast(__MODULE__, {:new_tx, hash, tx})
  end

  # Optional helper for a node to register itself as a peer
  def register_peer(pid) do
    GossipNode.PeerRegistry.add_peer(pid)
  end

  def init(state) do
    :timer.send_interval(@gossip_interval, :gossip)
    {:ok, state}
  end

  def handle_cast({:new_tx, hash, tx}, state) do
    pending = Map.update(state, :pending, [{hash, tx}], fn list -> [{hash, tx} | list] end)
    {:noreply, pending}
  end

  def handle_info(:gossip, state) do
    pending = Map.get(state, :pending, [])
    peers = GossipNode.PeerRegistry.list_peers()
    Enum.each(pending, fn {hash, tx} ->
      Enum.each(peers, fn pid ->
        GenServer.cast(pid, {:receive_tx, hash, tx})
      end)
    end)
    # Clear pending after broadcasting
    {:noreply, Map.delete(state, :pending)}
  end

  def handle_info({:peer_disconnected, pid}, state) do
    GossipNode.PeerRegistry.remove_peer(pid)
    {:noreply, state}
  end
end

defmodule GossipNode.PeerConnection do
  use GenServer

  def start_link(peer_pid) do
    GenServer.start_link(__MODULE__, peer_pid, name: {:peer_connection, peer_pid})
  end

  def init(peer_pid) do
    {:ok, peer_pid}
  end

  def handle_info({:tx, hash, tx}, peer_pid) do
    GossipNode.Mempool.submit_tx(tx)
    {:noreply, peer_pid}
  end

  def handle_info(:disconnect, peer_pid) do
    GenServer.cast(GossipNode.GossipServer, {:peer_disconnected, peer_pid})
    {:stop, :normal, peer_pid}
  end
end

defmodule GossipNode.PeerDiscovery do
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def discover_peers do
    GenServer.call(__MODULE__, :discover_peers)
  end

  def handle_call(:discover_peers, _from, state) do
    # Simulate peer discovery
    new_peers = [self(), self(), self()]
    {:reply, new_peers, state}
  end
end

defmodule GossipNode.PeerHandler do
  use GenServer

  def start_link(peer_pid) do
    GenServer.start_link(__MODULE__, peer_pid, name: {:peer_handler, peer_pid})
  end

  def init(peer_pid) do
    {:ok, peer_pid}
  end

  def handle_info({:tx, hash, tx}, peer_pid) do
    GossipNode.Mempool.submit_tx(tx)
    {:noreply, peer_pid}
  end

  def handle_info(:disconnect, peer_pid) do
    GenServer.cast(GossipNode.GossipServer, {:peer_disconnected, peer_pid})
    {:stop, :normal, peer_pid}
  end
end

defmodule GossipNode.PeerConnectionManager do
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def handle_info({:new_peer, peer_pid}, state) do
    GossipNode.PeerConnection.start_link(peer_pid)
    {:noreply, state}
  end

  def handle_info({:peer_disconnected, peer_pid}, state) do
    GenServer.cast(GossipNode.GossipServer, {:peer_disconnected, peer_pid})
    {:noreply, state}
  end
end
