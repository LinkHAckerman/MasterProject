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

  @type tx_hash :: binary
  @type tx :: map
  @type state :: MapSet.t(tx_hash)

  @type submit_tx :: {:submit_tx, tx}
  @type get_txs :: :get_txs
  @type receive_tx :: {:receive_tx, tx_hash, tx}
  @type call :: submit_tx | get_txs
  @type cast :: receive_tx

  @spec start_link(list) :: {:ok, pid} | {:error, term}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %MapSet{}, name: __MODULE__)
  end

  @spec submit_tx(tx) :: {:ok, tx_hash} | {:error, :duplicate}
  def submit_tx(tx) do
    GenServer.call(__MODULE__, {:submit_tx, tx})
  end

  @spec get_txs :: list(tx_hash)
  def get_txs do
    GenServer.call(__MODULE__, :get_txs)
  end

  @spec init(state) :: {:ok, state}
  def init(state) do
    {:ok, state}
  end

  @spec handle_call(call, from, state) :: {:reply, reply, state} | {:noreply, state} | {:stop, reason, state}
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

  @spec handle_call(call, from, state) :: {:reply, reply, state} | {:noreply, state} | {:stop, reason, state}
  def handle_call(:get_txs, _from, state) do
    {:reply, MapSet.to_list(state), state}
  end

  @spec handle_cast(cast, state) :: {:noreply, state} | {:stop, reason, state}
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

  @spec tx_hash(tx) :: tx_hash
  defp tx_hash(tx) do
    :crypto.hash(:sha256, :erlang.term_to_binary(tx))
    |> Base.encode16()
  end
end

defmodule GossipNode.PeerRegistry do
  @moduledoc false

  @type pid :: pid

  @spec add_peer(pid) :: :ok | {:error, term}
  def add_peer(pid) when is_pid(pid) do
    Registry.register(GossipNode.PeerRegistry, pid, %{})
  end

  @spec list_peers :: list(pid)
  def list_peers do
    Registry.select(GossipNode.PeerRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @spec remove_peer(pid) :: :ok | {:error, term}
  def remove_peer(pid) when is_pid(pid) do
    Registry.delete(GossipNode.PeerRegistry, pid)
  end

  @spec peer_exists?(pid) :: boolean
  def peer_exists?(pid) when is_pid(pid) do
    Registry.lookup(GossipNode.PeerRegistry, pid) != []
  end

  @spec count_peers :: non_neg_integer
  def count_peers do
    Registry.count(GossipNode.PeerRegistry)
  end
end

defmodule GossipNode.GossipServer do
  use GenServer

  @type tx_hash :: binary
  @type tx :: map
  @type state :: %{pending?: list({tx_hash, tx})}

  @type new_tx :: {:new_tx, tx_hash, tx}
  @type register_peer :: {:register_peer, pid}
  @type peer_disconnected :: {:peer_disconnected, pid}
  @type peer_connected :: {:peer_connected, pid}
  @type tx_info :: {:tx, tx_hash, tx}
  @type cast :: new_tx | register_peer | peer_disconnected | peer_connected | tx_info

  @gossip_interval 5_000 # milliseconds

  @spec start_link(list) :: {:ok, pid} | {:error, term}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @spec new_tx(tx_hash, tx) :: :ok
  def new_tx(hash, tx) do
    GenServer.cast(__MODULE__, {:new_tx, hash, tx})
  end

  @spec register_peer(pid) :: :ok
  def register_peer(pid) do
    GenServer.cast(__MODULE__, {:register_peer, pid})
  end

  @spec init(state) :: {:ok, state}
  def init(state) do
    :timer.send_interval(@gossip_interval, :gossip)
    {:ok, state}
  end

  @spec handle_cast(cast, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_cast({:new_tx, hash, tx}, state) do
    pending = Map.update(state, :pending, [{hash, tx}], fn list -> [{hash, tx} | list] end)
    {:noreply, pending}
  end

  @spec handle_cast(cast, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_cast({:register_peer, pid}, state) do
    GossipNode.PeerRegistry.add_peer(pid)
    {:noreply, state}
  end

  @spec handle_info(:gossip, state) :: {:noreply, state} | {:stop, reason, state}
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

  @spec handle_info(peer_disconnected, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info({:peer_disconnected, pid}, state) do
    GossipNode.PeerRegistry.remove_peer(pid)
    {:noreply, state}
  end

  @spec handle_info(peer_connected, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info({:peer_connected, pid}, state) do
    GossipNode.PeerRegistry.add_peer(pid)
    {:noreply, state}
  end

  @spec handle_info(tx_info, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info({:tx, hash, tx}, state) do
    GossipNode.Mempool.submit_tx(tx)
    {:noreply, state}
  end
end

defmodule GossipNode.PeerConnection do
  use GenServer

  @type tx_hash :: binary
  @type tx :: map
  @type state :: pid

  @type tx_info :: {:tx, tx_hash, tx}
  @type disconnect :: :disconnect
  @type info :: tx_info | disconnect

  @spec start_link(pid) :: {:ok, pid} | {:error, term}
  def start_link(peer_pid) do
    GenServer.start_link(__MODULE__, peer_pid, name: {:peer_connection, peer_pid})
  end

  @spec init(pid) :: {:ok, state}
  def init(peer_pid) do
    {:ok, peer_pid}
  end

  @spec handle_info(info, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info({:tx, hash, tx}, peer_pid) do
    GossipNode.Mempool.submit_tx(tx)
    {:noreply, peer_pid}
  end

  @spec handle_info(info, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info(:disconnect, peer_pid) do
    GenServer.cast(GossipNode.GossipServer, {:peer_disconnected, peer_pid})
    {:stop, :normal, peer_pid}
  end
end

defmodule GossipNode.PeerDiscovery do
  use GenServer

  @type state :: map

  @type discover_peers :: :discover_peers
  @type call :: discover_peers

  @spec start_link(list) :: {:ok, pid} | {:error, term}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @spec init(state) :: {:ok, state}
  def init(state) do
    {:ok, state}
  end

  @spec discover_peers :: list(pid)
  def discover_peers do
    GenServer.call(__MODULE__, :discover_peers)
  end

  @spec handle_call(call, from, state) :: {:reply, reply, state} | {:noreply, state} | {:stop, reason, state}
  def handle_call(:discover_peers, _from, state) do
    # Simulate peer discovery
    new_peers = [self(), self(), self()]
    {:reply, new_peers, state}
  end
end

defmodule GossipNode.PeerConnectionManager do
  use GenServer

  @type tx_hash :: binary
  @type tx :: map
  @type state :: map

  @type peer_connected :: {:peer_connected, pid}
  @type peer_disconnected :: {:peer_disconnected, pid}
  @type tx_info :: {:tx, tx_hash, tx}
  @type info :: peer_connected | peer_disconnected | tx_info

  @spec start_link(list) :: {:ok, pid} | {:error, term}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @spec init(state) :: {:ok, state}
  def init(state) do
    {:ok, state}
  end

  @spec handle_info(info, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info({:peer_connected, pid}, state) do
    GossipNode.PeerConnection.start_link(pid)
    {:noreply, state}
  end

  @spec handle_info(info, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info({:peer_disconnected, pid}, state) do
    GenServer.cast({:peer_connection, pid}, :disconnect)
    {:noreply, state}
  end

  @spec handle_info(info, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info({:tx, hash, tx}, state) do
    peers = GossipNode.PeerRegistry.list_peers()
    Enum.each(peers, fn pid ->
      GenServer.cast({:peer_connection, pid}, {:tx, hash, tx})
    end)
    {:noreply, state}
  end
end
