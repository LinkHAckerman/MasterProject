defmodule GossipNode.Application do
  @moduledoc """
  The GossipNode application module.
  
  This module defines the main application for the GossipNode system.
  It starts the necessary supervisors and children processes.
  """
  use Application

  @doc """
  Starts the GossipNode application.
  
  ## Parameters
    - type: The type of the application.
    - args: The arguments passed to the application.
  
  ## Examples
    ```elixir
    GossipNode.Application.start(:normal, [])
    ```
  """
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
  @moduledoc """
  The GossipNode Mempool module.
  
  This module defines the mempool for the GossipNode system.
  It handles the submission and retrieval of transactions.
  """
  use GenServer

  @type tx_hash :: binary
  @type tx :: map
  @type state :: MapSet.t(tx_hash)

  @type submit_tx :: {:submit_tx, tx}
  @type get_txs :: :get_txs
  @type receive_tx :: {:receive_tx, tx_hash, tx}
  @type call :: submit_tx | get_txs
  @type cast :: receive_tx

  @doc """
  Starts the Mempool GenServer.
  
  ## Parameters
    - args: The arguments passed to the GenServer.
  
  ## Examples
    ```elixir
    {:ok, pid} = GossipNode.Mempool.start_link([])
    ```
  """
  @spec start_link(list) :: {:ok, pid} | {:error, term}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %MapSet{}, name: __MODULE__)
  end

  @doc """
  Submits a transaction to the mempool.
  
  ## Parameters
    - tx: The transaction to submit.
  
  ## Examples
    ```elixir
    {:ok, hash} = GossipNode.Mempool.submit_tx(%{data: "tx_data"})
    ```
  """
  @spec submit_tx(tx) :: {:ok, tx_hash} | {:error, :duplicate}
  def submit_tx(tx) do
    GenServer.call(__MODULE__, {:submit_tx, tx})
  end

  @doc """
  Retrieves all transactions from the mempool.
  
  ## Examples
    ```elixir
    txs = GossipNode.Mempool.get_txs()
    ```
  """
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
  @moduledoc """
  The GossipNode PeerRegistry module.
  
  This module defines the peer registry for the GossipNode system.
  It handles the registration, listing, and removal of peers.
  """
  @type pid :: pid

  @doc """
  Adds a peer to the registry.
  
  ## Parameters
    - pid: The process ID of the peer to add.
  
  ## Examples
    ```elixir
    GossipNode.PeerRegistry.add_peer(self())
    ```
  """
  @spec add_peer(pid) :: :ok | {:error, term}
  def add_peer(pid) when is_pid(pid) do
    Registry.register(GossipNode.PeerRegistry, pid, %{})
  end

  @doc """
  Lists all peers in the registry.
  
  ## Examples
    ```elixir
    peers = GossipNode.PeerRegistry.list_peers()
    ```
  """
  @spec list_peers :: list(pid)
  def list_peers do
    Registry.select(GossipNode.PeerRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  Removes a peer from the registry.
  
  ## Parameters
    - pid: The process ID of the peer to remove.
  
  ## Examples
    ```elixir
    GossipNode.PeerRegistry.remove_peer(self())
    ```
  """
  @spec remove_peer(pid) :: :ok | {:error, term}
  def remove_peer(pid) when is_pid(pid) do
    Registry.delete(GossipNode.PeerRegistry, pid)
  end

  @doc """
  Checks if a peer exists in the registry.
  
  ## Parameters
    - pid: The process ID of the peer to check.
  
  ## Examples
    ```elixir
    exists = GossipNode.PeerRegistry.peer_exists?(self())
    ```
  """
  @spec peer_exists?(pid) :: boolean
  def peer_exists?(pid) when is_pid(pid) do
    Registry.lookup(GossipNode.PeerRegistry, pid) != []
  end

  @doc """
  Counts the number of peers in the registry.
  
  ## Examples
    ```elixir
    count = GossipNode.PeerRegistry.count_peers()
    ```
  """
  @spec count_peers :: non_neg_integer
  def count_peers do
    Registry.count(GossipNode.PeerRegistry)
  end
end

defmodule GossipNode.GossipServer do
  @moduledoc """
  The GossipNode GossipServer module.
  
  This module defines the gossip server for the GossipNode system.
  It handles the broadcasting of transactions to peers and manages the state of the gossip server.
  """
  use GenServer

  @type tx_hash :: binary
  @type tx :: map
  @type state :: %{pending?: list({tx_hash, tx}), messages_sent: non_neg_integer, messages_received: non_neg_integer, messages_dropped: non_neg_integer}

  @type new_tx :: {:new_tx, tx_hash, tx}
  @type register_peer :: {:register_peer, pid}
  @type peer_disconnected :: {:peer_disconnected, pid}
  @type peer_connected :: {:peer_connected, pid}
  @type tx_info :: {:tx, tx_hash, tx}
  @type cast :: new_tx | register_peer | peer_disconnected | peer_connected | tx_info

  @gossip_interval 5_000 # milliseconds

  @doc """
  Starts the GossipServer GenServer.
  
  ## Parameters
    - args: The arguments passed to the GenServer.
  
  ## Examples
    ```elixir
    {:ok, pid} = GossipNode.GossipServer.start_link([])
    ```
  """
  @spec start_link(list) :: {:ok, pid} | {:error, term}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{messages_sent: 0, messages_received: 0, messages_dropped: 0}, name: __MODULE__)
  end

  @doc """
  Notifies the gossip server about a new transaction.
  
  ## Parameters
    - hash: The hash of the transaction.
    - tx: The transaction.
  
  ## Examples
    ```elixir
    GossipNode.GossipServer.new_tx("tx_hash", %{data: "tx_data"})
    ```
  """
  @spec new_tx(tx_hash, tx) :: :ok
  def new_tx(hash, tx) do
    GenServer.cast(__MODULE__, {:new_tx, hash, tx})
  end

  @doc """
  Registers a peer with the gossip server.
  
  ## Parameters
    - pid: The process ID of the peer.
  
  ## Examples
    ```elixir
    GossipNode.GossipServer.register_peer(self())
    ```
  """
  @spec register_peer(pid) :: :ok
  def register_peer(pid) do
    GenServer.cast(__MODULE__, {:register_peer, pid})
  end

  @doc """
  Retrieves the status of the gossip server.
  
  ## Examples
    ```elixir
    status = GossipNode.GossipServer.status()
    ```
  """
  @spec status :: map
  def status do
    GenServer.call(__MODULE__, :status)
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
        state = Map.update(state, :messages_sent, 1, &(&1 + 1))
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
    state = Map.update(state, :messages_received, 1, &(&1 + 1))
    {:noreply, state}
  end

  @spec handle_call(:status, _from, state) :: {:reply, map, state}
  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end
end

defmodule GossipNode.PeerConnection do
  @moduledoc """
  The GossipNode PeerConnection module.
  
  This module defines the peer connection for the GossipNode system.
  It handles the communication between peers and manages the state of the peer connection.
  """
  use GenServer

  @type tx_hash :: binary
  @type tx :: map
  @type state :: pid

  @type tx_info :: {:tx, tx_hash, tx}
  @type disconnect :: :disconnect
  @type info :: tx_info | disconnect

  @doc """
  Starts the PeerConnection GenServer.
  
  ## Parameters
    - peer_pid: The process ID of the peer.
  
  ## Examples
    ```elixir
    {:ok, pid} = GossipNode.PeerConnection.start_link(self())
    ```
  """
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
  @moduledoc """
  The GossipNode PeerDiscovery module.
  
  This module defines the peer discovery for the GossipNode system.
  It handles the discovery of new peers.
  """
  use GenServer

  @type state :: map

  @type discover_peers :: :discover_peers
  @type call :: discover_peers

  @doc """
  Starts the PeerDiscovery GenServer.
  
  ## Parameters
    - args: The arguments passed to the GenServer.
  
  ## Examples
    ```elixir
    {:ok, pid} = GossipNode.PeerDiscovery.start_link([])
    ```
  """
  @spec start_link(list) :: {:ok, pid} | {:error, term}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @spec init(state) :: {:ok, state}
  def init(state) do
    {:ok, state}
  end

  @doc """
  Discovers new peers.
  
  ## Examples
    ```elixir
    peers = GossipNode.PeerDiscovery.discover_peers()
    ```
  """
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
  @moduledoc """
  The GossipNode PeerConnectionManager module.
  
  This module defines the peer connection manager for the GossipNode system.
  It handles the management of peer connections.
  """
  use GenServer

  @type tx_hash :: binary
  @type tx :: map
  @type state :: map

  @type peer_connected :: {:peer_connected, pid}
  @type peer_disconnected :: {:peer_disconnected, pid}
  @type tx_info :: {:tx, tx_hash, tx}
  @type info :: peer_connected | peer_disconnected | tx_info

  @doc """
  Starts the PeerConnectionManager GenServer.
  
  ## Parameters
    - args: The arguments passed to the GenServer.
  
  ## Examples
    ```elixir
    {:ok, pid} = GossipNode.PeerConnectionManager.start_link([])
    ```
  """
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
    GossipNode.Mempool.submit_tx(tx)
    {:noreply, state}
  end
end

defmodule GossipNodeTest do
  use ExUnit.Case

  test "Mempool submit_tx and get_txs" do
    {:ok, pid} = GossipNode.Mempool.start_link([])
    tx = %{data: "tx_data"}
    {:ok, hash} = GossipNode.Mempool.submit_tx(tx)
    assert GossipNode.Mempool.get_txs() == [hash]
  end

  test "PeerRegistry add_peer, list_peers, and remove_peer" do
    pid = self()
    assert GossipNode.PeerRegistry.add_peer(pid) == :ok
    assert GossipNode.PeerRegistry.list_peers() == [pid]
    assert GossipNode.PeerRegistry.remove_peer(pid) == :ok
    assert GossipNode.PeerRegistry.list_peers() == []
  end

  test "GossipServer new_tx and status" do
    {:ok, pid} = GossipNode.GossipServer.start_link([])
    hash = "tx_hash"
    tx = %{data: "tx_data"}
    assert GossipNode.GossipServer.new_tx(hash, tx) == :ok
    assert Map.has_key?(GossipNode.GossipServer.status(), :messages_sent)
  end

  test "PeerDiscovery discover_peers" do
    {:ok, pid} = GossipNode.PeerDiscovery.start_link([])
    assert is_list(GossipNode.PeerDiscovery.discover_peers())
  end
end
