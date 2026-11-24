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
      {GossipNode.PeerConnectionManager, []},
      {GossipNode.PeerSampling, []}
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
    Registry.register(GossipNode.PeerRegistry, pid, %{score: 0, banned: false})
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

  @doc """
  Updates the score of a peer.
  
  ## Parameters
    - pid: The process ID of the peer.
    - delta: The amount to adjust the score by.
  
  ## Examples
    ```elixir
    GossipNode.PeerRegistry.update_score(self(), 1)
    ```
  """
  @spec update_score(pid, integer) :: :ok | {:error, term}
  def update_score(pid, delta) when is_pid(pid) do
    Registry.update(GossipNode.PeerRegistry, pid, fn peer ->
      %{peer | score: peer.score + delta}
    end)
  end

  @doc """
  Bans a peer.
  
  ## Parameters
    - pid: The process ID of the peer to ban.
  
  ## Examples
    ```elixir
    GossipNode.PeerRegistry.ban_peer(self())
    ```
  """
  @spec ban_peer(pid) :: :ok | {:error, term}
  def ban_peer(pid) when is_pid(pid) do
    Registry.update(GossipNode.PeerRegistry, pid, fn peer ->
      %{peer | banned: true}
    end)
  end

  @doc """
  Checks if a peer is banned.
  
  ## Parameters
    - pid: The process ID of the peer to check.
  
  ## Examples
    ```elixir
    banned = GossipNode.PeerRegistry.peer_banned?(self())
    ```
  """
  @spec peer_banned?(pid) :: boolean
  def peer_banned?(pid) when is_pid(pid) do
    case Registry.lookup(GossipNode.PeerRegistry, pid) do
      [peer] -> peer.banned
      _ -> false
    end
  end

  @doc """
  Gets the score of a peer.
  
  ## Parameters
    - pid: The process ID of the peer.
  
  ## Examples
    ```elixir
    score = GossipNode.PeerRegistry.get_score(self())
    ```
  """
  @spec get_score(pid) :: integer | nil
  def get_score(pid) when is_pid(pid) do
    case Registry.lookup(GossipNode.PeerRegistry, pid) do
      [peer] -> peer.score
      _ -> nil
    end
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
  @type state :: %{pending?: list({tx_hash, tx}), messages_sent: non_neg_integer, messages_received: non_neg_integer, messages_dropped: non_neg_integer, fanout: non_neg_integer, ttl: non_neg_integer, backoff: non_neg_integer}

  @type new_tx :: {:new_tx, tx_hash, tx}
  @type register_peer :: {:register_peer, pid}
  @type peer_disconnected :: {:peer_disconnected, pid}
  @type peer_connected :: {:peer_connected, pid}
  @type tx_info :: {:tx, tx_hash, tx}
  @type cast :: new_tx | register_peer | peer_disconnected | peer_connected | tx_info

  @gossip_interval 5_000 # milliseconds
  @ban_threshold -10
  @score_increment 1
  @score_decrement -1

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
    GenServer.start_link(__MODULE__, %{messages_sent: 0, messages_received: 0, messages_dropped: 0, fanout: 3, ttl: 10, backoff: 1000}, name: __MODULE__)
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
  Notifies the gossip server that a peer has disconnected.
  
  ## Parameters
    - pid: The process ID of the peer.
  
  ## Examples
    ```elixir
    GossipNode.GossipServer.peer_disconnected(self())
    ```
  """
  @spec peer_disconnected(pid) :: :ok
  def peer_disconnected(pid) do
    GenServer.cast(__MODULE__, {:peer_disconnected, pid})
  end

  @doc """
  Notifies the gossip server that a peer has connected.
  
  ## Parameters
    - pid: The process ID of the peer.
  
  ## Examples
    ```elixir
    GossipNode.GossipServer.peer_connected(self())
    ```
  """
  @spec peer_connected(pid) :: :ok
  def peer_connected(pid) do
    GenServer.cast(__MODULE__, {:peer_connected, pid})
  end

  @doc """
  Notifies the gossip server about a transaction received from a peer.
  
  ## Parameters
    - hash: The hash of the transaction.
    - tx: The transaction.
  
  ## Examples
    ```elixir
    GossipNode.GossipServer.tx_info("tx_hash", %{data: "tx_data"})
    ```
  """
  @spec tx_info(tx_hash, tx) :: :ok
  def tx_info(hash, tx) do
    GenServer.cast(__MODULE__, {:tx, hash, tx})
  end

  @spec init(state) :: {:ok, state}
  def init(state) do
    {:ok, state}
  end

  @spec handle_cast(cast, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_cast({:new_tx, hash, tx}, state) do
    new_state = Map.put(state, :pending, [{hash, tx} | state[:pending] || []])
    {:noreply, new_state}
  end

  @spec handle_cast(cast, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_cast({:register_peer, pid}, state) do
    GossipNode.PeerRegistry.add_peer(pid)
    {:noreply, state}
  end

  @spec handle_cast(cast, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_cast({:peer_disconnected, pid}, state) do
    GossipNode.PeerRegistry.remove_peer(pid)
    {:noreply, state}
  end

  @spec handle_cast(cast, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_cast({:peer_connected, pid}, state) do
    GossipNode.PeerRegistry.add_peer(pid)
    {:noreply, state}
  end

  @spec handle_cast(cast, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_cast({:tx, hash, tx}, state) do
    GossipNode.Mempool.receive_tx(hash, tx)
    {:noreply, state}
  end

  @spec handle_info(info, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info(:gossip, state) do
    peers = GossipNode.PeerRegistry.list_peers()
    pending = state[:pending] || []
    fanout = state[:fanout]

    # Select a random subset of peers to gossip to
    selected_peers = Enum.take(Enum.shuffle(peers), fanout)

    # Select a random subset of pending transactions to gossip
    selected_txs = Enum.take(Enum.shuffle(pending), fanout)

    # Send the selected transactions to the selected peers
    for {hash, tx} <- selected_txs do
      for peer <- selected_peers do
        send(peer, {:tx, hash, tx})
      end
    end

    # Update the state with the remaining pending transactions
    remaining_txs = pending -- selected_txs
    new_state = Map.put(state, :pending, remaining_txs)

    # Schedule the next gossip
    Process.send_after(self(), :gossip, @gossip_interval)

    {:noreply, new_state}
  end

  @spec handle_info(info, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info(:timeout, state) do
    # Handle timeout
    {:noreply, state}
  end

  @spec handle_info(info, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info(_info, state) do
    {:noreply, state}
  end

  @spec code_change(version, state, extra) :: {:ok, state}
  def code_change(_version, state, _extra) do
    {:ok, state}
  end
end

defmodule GossipNode.PeerSampling do
  @moduledoc """
  The GossipNode PeerSampling module.
  
  This module defines the peer sampling for the GossipNode system.
  It handles the periodic shuffle and failure detection of peers.
  """
  use GenServer

  @type pid :: pid
  @type state :: %{peers: list(pid), active_peers: list(pid), suspicion_timeout: non_neg_integer, heartbeat_interval: non_neg_integer}

  @type register_peer :: {:register_peer, pid}
  @type peer_disconnected :: {:peer_disconnected, pid}
  @type peer_connected :: {:peer_connected, pid}
  @type heartbeat :: {:heartbeat, pid}
  @type cast :: register_peer | peer_disconnected | peer_connected | heartbeat

  @suspicion_timeout 30_000 # milliseconds
  @heartbeat_interval 10_000 # milliseconds
  @shuffle_interval 60_000 # milliseconds

  @doc """
  Starts the PeerSampling GenServer.
  
  ## Parameters
    - args: The arguments passed to the GenServer.
  
  ## Examples
    ```elixir
    {:ok, pid} = GossipNode.PeerSampling.start_link([])
    ```
  """
  @spec start_link(list) :: {:ok, pid} | {:error, term}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{peers: [], active_peers: [], suspicion_timeout: @suspicion_timeout, heartbeat_interval: @heartbeat_interval}, name: __MODULE__)
  end

  @doc """
  Registers a peer with the peer sampling.
  
  ## Parameters
    - pid: The process ID of the peer.
  
  ## Examples
    ```elixir
    GossipNode.PeerSampling.register_peer(self())
    ```
  """
  @spec register_peer(pid) :: :ok
  def register_peer(pid) do
    GenServer.cast(__MODULE__, {:register_peer, pid})
  end

  @doc """
  Notifies the peer sampling that a peer has disconnected.
  
  ## Parameters
    - pid: The process ID of the peer.
  
  ## Examples
    ```elixir
    GossipNode.PeerSampling.peer_disconnected(self())
    ```
  """
  @spec peer_disconnected(pid) :: :ok
  def peer_disconnected(pid) do
    GenServer.cast(__MODULE__, {:peer_disconnected, pid})
  end

  @doc """
  Notifies the peer sampling that a peer has connected.
  
  ## Parameters
    - pid: The process ID of the peer.
  
  ## Examples
    ```elixir
    GossipNode.PeerSampling.peer_connected(self())
    ```
  """
  @spec peer_connected(pid) :: :ok
  def peer_connected(pid) do
    GenServer.cast(__MODULE__, {:peer_connected, pid})
  end

  @doc """
  Notifies the peer sampling about a heartbeat from a peer.
  
  ## Parameters
    - pid: The process ID of the peer.
  
  ## Examples
    ```elixir
    GossipNode.PeerSampling.heartbeat(self())
    ```
  """
  @spec heartbeat(pid) :: :ok
  def heartbeat(pid) do
    GenServer.cast(__MODULE__, {:heartbeat, pid})
  end

  @spec init(state) :: {:ok, state}
  def init(state) do
    # Schedule the first heartbeat and shuffle
    Process.send_after(self(), :heartbeat, state[:heartbeat_interval])
    Process.send_after(self(), :shuffle, @shuffle_interval)
    {:ok, state}
  end

  @spec handle_cast(cast, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_cast({:register_peer, pid}, state) do
    new_state = Map.update!(state, :peers, [pid], &[pid | &1])
    {:noreply, new_state}
  end

  @spec handle_cast(cast, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_cast({:peer_disconnected, pid}, state) do
    new_state = Map.update!(state, :peers, &Enum.delete(&1, pid))
    new_state = Map.update!(new_state, :active_peers, &Enum.delete(&1, pid))
    {:noreply, new_state}
  end

  @spec handle_cast(cast, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_cast({:peer_connected, pid}, state) do
    new_state = Map.update!(state, :peers, [pid], &[pid | &1])
    new_state = Map.update!(new_state, :active_peers, [pid], &[pid | &1])
    {:noreply, new_state}
  end

  @spec handle_cast(cast, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_cast({:heartbeat, pid}, state) do
    if Enum.member?(state[:active_peers], pid) do
      # Reset the suspicion timeout for the peer
      Process.send_after(self(), {:suspicion, pid}, state[:suspicion_timeout])
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @spec handle_info(info, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info(:heartbeat, state) do
    # Send heartbeats to all active peers
    for pid <- state[:active_peers] do
      send(pid, :heartbeat)
    end

    # Schedule the next heartbeat
    Process.send_after(self(), :heartbeat, state[:heartbeat_interval])

    {:noreply, state}
  end

  @spec handle_info(info, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info({:suspicion, pid}, state) do
    if Enum.member?(state[:active_peers], pid) do
      # Peer has not responded to heartbeat, mark as disconnected
      new_state = Map.update!(state, :active_peers, &Enum.delete(&1, pid))
      GossipNode.GossipServer.peer_disconnected(pid)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @spec handle_info(info, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info(:shuffle, state) do
    # Shuffle the active peers
    new_active_peers = Enum.shuffle(state[:active_peers])
    new_state = Map.put(state, :active_peers, new_active_peers)

    # Schedule the next shuffle
    Process.send_after(self(), :shuffle, @shuffle_interval)

    {:noreply, new_state}
  end

  @spec handle_info(info, state) :: {:noreply, state} | {:stop, reason, state}
  def handle_info(_info, state) do
    {:noreply, state}
  end

  @spec code_change(version, state, extra) :: {:ok, state}
  def code_change(_version, state, _extra) do
    {:ok, state}
  end
end
