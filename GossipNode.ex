defmodule GossipNode.Protocol do
  @moduledoc """
  Typed message protocol and schema validation for the GossipNode system.
  Provides explicit type specifications, binary/term encoding & decoding,
  and comprehensive validation for all incoming and outgoing P2P messages.
  """

  @type tx_hash :: binary()
  @type timestamp :: non_neg_integer()
  @type peer_id :: pid() | binary()

  @type tx_payload :: %{
          required(:from) => binary(),
          required(:to) => binary(),
          required(:amount) => non_neg_integer(),
          required(:nonce) => non_neg_integer(),
          optional(:signature) => binary(),
          optional(:data) => binary()
        }

  @type msg_tx :: %{
          required(:type) => :tx,
          required(:hash) => tx_hash(),
          required(:tx) => tx_payload(),
          required(:ttl) => pos_integer(),
          optional(:sender) => peer_id()
        }

  @type msg_ping :: %{
          required(:type) => :ping,
          required(:sender) => peer_id(),
          required(:timestamp) => timestamp()
        }

  @type msg_pong :: %{
          required(:type) => :pong,
          required(:sender) => peer_id(),
          required(:timestamp) => timestamp()
        }

  @type msg_peers :: %{
          required(:type) => :peers,
          required(:sender) => peer_id(),
          required(:peers) => list(peer_id())
        }

  @type gossip_message :: msg_tx() | msg_ping() | msg_pong() | msg_peers()

  @doc """
  Validates an incoming gossip message according to strict protocol schemas.
  """
  @spec validate_msg(term()) :: {:ok, gossip_message()} | {:error, atom()}
  def validate_msg(%{type: :tx} = msg) do
    with :ok <- check_field(msg, :hash, &is_binary/1),
         :ok <- check_field(msg, :tx, &is_map/1),
         :ok <- check_field(msg, :ttl, fn v -> is_integer(v) and v > 0 end),
         :ok <- validate_tx_payload(msg.tx) do
      {:ok, msg}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_msg(%{type: :ping} = msg) do
    with :ok <- check_field(msg, :sender, &valid_peer_id?/1),
         :ok <- check_field(msg, :timestamp, &is_integer/1) do
      {:ok, msg}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_msg(%{type: :pong} = msg) do
    with :ok <- check_field(msg, :sender, &valid_peer_id?/1),
         :ok <- check_field(msg, :timestamp, &is_integer/1) do
      {:ok, msg}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_msg(%{type: :peers} = msg) do
    with :ok <- check_field(msg, :sender, &valid_peer_id?/1),
         :ok <- check_field(msg, :peers, &is_list/1) do
      if Enum.all?(msg.peers, &valid_peer_id?/1) do
        {:ok, msg}
      else
        {:error, :invalid_peers_list}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_msg(_), do: {:error, :unknown_message_type}

  @doc """
  Validates transaction payload fields.
  """
  @spec validate_tx_payload(term()) :: :ok | {:error, atom()}
  def validate_tx_payload(%{} = tx) do
    from = Map.get(tx, :from) || Map.get(tx, "from")
    to = Map.get(tx, :to) || Map.get(tx, "to")
    amount = Map.get(tx, :amount) || Map.get(tx, "amount")

    cond do
      is_nil(from) or not is_binary(from) -> {:error, :invalid_tx_from}
      is_nil(to) or not is_binary(to) -> {:error, :invalid_tx_to}
      is_nil(amount) or not is_integer(amount) or amount < 0 -> {:error, :invalid_tx_amount}
      true -> :ok
    end
  end

  def validate_tx_payload(_), do: {:error, :invalid_tx_format}

  @doc """
  Helper function to check presence and predicate matching for map fields.
  """
  @spec check_field(map(), atom(), (term() -> boolean())) :: :ok | {:error, atom()}
  def check_field(map, field, predicate) when is_map(map) and is_atom(field) do
    case Map.fetch(map, field) do
      {:ok, val} ->
        if predicate.(val) do
          :ok
        else
          {:error, :"invalid_field_#{field}"}
        end

      :error ->
        {:error, :"missing_field_#{field}"}
    end
  end

  @doc """
  Checks if a given term is a valid peer identity.
  """
  @spec valid_peer_id?(term()) :: boolean()
  def valid_peer_id?(pid) when is_pid(pid), do: true
  def valid_peer_id?(bin) when is_binary(bin) and byte_size(bin) > 0, do: true
  def valid_peer_id?(_), do: false

  @doc """
  Encodes a gossip message into binary payload.
  """
  @spec encode(gossip_message()) :: {:ok, binary()} | {:error, term()}
  def encode(msg) do
    case validate_msg(msg) do
      {:ok, valid_msg} -> {:ok, :erlang.term_to_binary(valid_msg)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Decodes binary payload into a validated gossip message.
  """
  @spec decode(binary()) :: {:ok, gossip_message()} | {:error, term()}
  def decode(binary) when is_binary(binary) do
    try do
      term = :erlang.binary_to_term(binary, [:safe])
      validate_msg(term)
    rescue
      _ -> {:error, :corrupted_payload}
    end
  end

  def decode(_), do: {:error, :invalid_binary_input}
end

defmodule GossipNode.Application do
  @moduledoc """
  The GossipNode application module.
  Starts supervisors, peer registry, mempool, gossip engine, and auxiliary services.
  """
  use Application

  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
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
  Handles transaction validation, deduplication, and memory storage.
  """
  use GenServer

  alias GossipNode.Protocol

  @type tx_hash :: binary()
  @type tx :: map()
  @type state :: MapSet.t(tx_hash)

  @spec start_link(list()) :: {:ok, pid()} | {:error, term()}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, MapSet.new(), name: __MODULE__)
  end

  @doc """
  Submits a raw transaction to the mempool after verifying its payload structure.
  """
  @spec submit_tx(tx()) :: {:ok, tx_hash()} | {:error, term()}
  def submit_tx(tx) do
    case Protocol.validate_tx_payload(tx) do
      :ok -> GenServer.call(__MODULE__, {:submit_tx, tx})
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieves all known transaction hashes from the mempool.
  """
  @spec get_txs() :: list(tx_hash())
  def get_txs do
    GenServer.call(__MODULE__, :get_txs)
  end

  @doc """
  Receives an incoming transaction broadcast hash & payload.
  """
  @spec receive_tx(tx_hash(), tx()) :: :ok | {:error, term()}
  def receive_tx(hash, tx) do
    GenServer.cast(__MODULE__, {:receive_tx, hash, tx})
  end

  @impl true
  @spec init(state()) :: {:ok, state()}
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:submit_tx, tx}, _from, state) do
    hash = tx_hash(tx)
    if MapSet.member?(state, hash) do
      {:reply, {:error, :duplicate}, state}
    else
      new_state = MapSet.put(state, hash)
      GossipNode.GossipServer.new_tx(hash, tx)
      {:reply, {:ok, hash}, new_state}
    end
  end

  def handle_call(:get_txs, _from, state) do
    {:reply, MapSet.to_list(state), state}
  end

  @impl true
  def handle_cast({:receive_tx, hash, tx}, state) do
    if MapSet.member?(state, hash) do
      {:noreply, state}
    else
      new_state = MapSet.put(state, hash)
      GossipNode.GossipServer.new_tx(hash, tx)
      {:noreply, new_state}
    end
  end

  @spec tx_hash(tx()) :: tx_hash()
  defp tx_hash(tx) do
    :crypto.hash(:sha256, :erlang.term_to_binary(tx))
    |> Base.encode16(case: :lower)
  end
end

defmodule GossipNode.PeerRegistry do
  @moduledoc """
  The GossipNode PeerRegistry module.
  Manages peer registration, reputation metrics, bans, and dynamic discovery querying.
  """
  @type peer_meta :: %{score: integer(), banned: boolean()}

  @spec add_peer(pid()) :: :ok | {:error, term()}
  def add_peer(pid) when is_pid(pid) do
    case Registry.register(GossipNode.PeerRegistry, pid, %{score: 0, banned: false}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list_peers() :: list(pid())
  def list_peers do
    Registry.select(GossipNode.PeerRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @spec remove_peer(pid()) :: :ok
  def remove_peer(pid) when is_pid(pid) do
    Registry.unregister(GossipNode.PeerRegistry, pid)
  end

  @spec peer_exists?(pid()) :: boolean()
  def peer_exists?(pid) when is_pid(pid) do
    Registry.lookup(GossipNode.PeerRegistry, pid) != []
  end

  @spec count_peers() :: non_neg_integer()
  def count_peers do
    Registry.count(GossipNode.PeerRegistry)
  end

  @spec update_score(pid(), integer()) :: :ok | {:error, term()}
  def update_score(pid, delta) when is_pid(pid) and is_integer(delta) do
    case Registry.update_value(GossipNode.PeerRegistry, pid, fn meta ->
           %{meta | score: meta.score + delta}
         end) do
      {_new, _old} -> :ok
      :error -> {:error, :peer_not_found}
    end
  end

  @spec ban_peer(pid()) :: :ok | {:error, term()}
  def ban_peer(pid) when is_pid(pid) do
    case Registry.update_value(GossipNode.PeerRegistry, pid, fn meta ->
           %{meta | banned: true}
         end) do
      {_new, _old} -> :ok
      :error -> {:error, :peer_not_found}
    end
  end

  @spec peer_banned?(pid()) :: boolean()
  def peer_banned?(pid) when is_pid(pid) do
    case Registry.lookup(GossipNode.PeerRegistry, pid) do
      [{_pid, meta}] -> meta.banned
      _ -> false
    end
  end

  @spec get_score(pid()) :: integer() | nil
  def get_score(pid) when is_pid(pid) do
    case Registry.lookup(GossipNode.PeerRegistry, pid) do
      [{_pid, meta}] -> meta.score
      _ -> nil
    end
  end
end

defmodule GossipNode.GossipServer do
  @moduledoc """
  The GossipNode GossipServer module.
  Handles transaction broadcasting, incoming message validation, fanout selection,
  and epidemic propagation across registered peers.
  """
  use GenServer

  alias GossipNode.Protocol
  alias GossipNode.PeerRegistry

  @type tx_hash :: binary()
  @type tx :: map()
  @type state :: %{
          pending: list({tx_hash(), tx()}),
          messages_sent: non_neg_integer(),
          messages_received: non_neg_integer(),
          messages_dropped: non_neg_integer(),
          fanout: non_neg_integer(),
          ttl: non_neg_integer()
        }

  @spec start_link(list()) :: {:ok, pid()} | {:error, term()}
  def start_link(_args) do
    initial_state = %{
      pending: [],
      messages_sent: 0,
      messages_received: 0,
      messages_dropped: 0,
      fanout: 3,
      ttl: 10
    }

    GenServer.start_link(__MODULE__, initial_state, name: __MODULE__)
  end

  @spec new_tx(tx_hash(), tx()) :: :ok
  def new_tx(hash, tx) do
    msg = %{type: :tx, hash: hash, tx: tx, ttl: 10, sender: self()}

    case Protocol.validate_msg(msg) do
      {:ok, valid_msg} -> GenServer.cast(__MODULE__, {:new_tx_msg, valid_msg})
      {:error, _reason} -> :ok
    end
  end

  @spec incoming_msg(term()) :: :ok | {:error, term()}
  def incoming_msg(raw_msg) do
    case Protocol.validate_msg(raw_msg) do
      {:ok, valid_msg} -> GenServer.cast(__MODULE__, {:process_msg, valid_msg, self()})
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  @spec init(state()) :: {:ok, state()}
  def init(state) do
    schedule_gossip()
    {:ok, state}
  end

  @impl true
  def handle_cast({:new_tx_msg, %{hash: hash, tx: tx}}, state) do
    new_pending = [{hash, tx} | state.pending]
    {:noreply, %{state | pending: new_pending}}
  end

  def handle_cast({:process_msg, %{type: :tx, hash: hash, tx: tx, ttl: ttl}, sender}, state) do
    if PeerRegistry.peer_banned?(sender) do
      {:noreply, %{state | messages_dropped: state.messages_dropped + 1}}
    else
      PeerRegistry.update_score(sender, 1)
      GossipNode.Mempool.receive_tx(hash, tx)

      if ttl > 1 do
        relayed_msg = %{type: :tx, hash: hash, tx: tx, ttl: ttl - 1, sender: self()}
        broadcast_to_fanout(relayed_msg, state.fanout, [sender])
      end

      {:noreply, %{state | messages_received: state.messages_received + 1}}
    end
  end

  def handle_cast({:process_msg, %{type: :ping, sender: sender, timestamp: ts}, _pid}, state) do
    pong = %{type: :pong, sender: self(), timestamp: ts}
    if is_pid(sender), do: send(sender, {:gossip_msg, pong})
    {:noreply, %{state | messages_received: state.messages_received + 1}}
  end

  def handle_cast({:process_msg, %{type: :pong, sender: sender}, _pid}, state) do
    if is_pid(sender), do: PeerRegistry.update_score(sender, 1)
    {:noreply, %{state | messages_received: state.messages_received + 1}}
  end

  def handle_cast({:process_msg, _unhandled, _sender}, state) do
    {:noreply, %{state | messages_dropped: state.messages_dropped + 1}}
  end

  @impl true
  def handle_info(:gossip_tick, state) do
    if state.pending != [] do
      Enum.each(state.pending, fn {hash, tx} ->
        msg = %{type: :tx, hash: hash, tx: tx, ttl: state.ttl, sender: self()}
        broadcast_to_fanout(msg, state.fanout, [])
      end)
    end

    schedule_gossip()
    {:noreply, %{state | pending: [], messages_sent: state.messages_sent + length(state.pending)}}
  end

  defp broadcast_to_fanout(msg, fanout, exclude) do
    peers = PeerRegistry.list_peers() -- exclude
    targets = Enum.take_random(peers, fanout)

    Enum.each(targets, fn peer ->
      if is_pid(peer) and Process.alive?(peer) do
        send(peer, {:gossip_msg, msg})
      end
    end)
  end

  defp schedule_gossip do
    Process.send_after(self(), :gossip_tick, 3000)
  end
end

defmodule GossipNode.PeerDiscovery do
  @moduledoc """
  The GossipNode PeerDiscovery module.
  Handles peer discovery, seed nodes, and exchange of active peer addresses.
  """
  use GenServer

  alias GossipNode.Protocol
  alias GossipNode.PeerRegistry

  @spec start_link(list()) :: {:ok, pid()} | {:error, term()}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_discovery()
    {:ok, state}
  end

  @impl true
  def handle_info(:discover_peers, state) do
    peers = PeerRegistry.list_peers()
    msg = %{type: :peers, sender: self(), peers: peers}

    case Protocol.validate_msg(msg) do
      {:ok, valid_msg} ->
        Enum.each(peers, fn peer ->
          if is_pid(peer) and Process.alive?(peer) do
            send(peer, {:gossip_msg, valid_msg})
          end
        end)

      _ ->
        :ok
    end

    schedule_discovery()
    {:noreply, state}
  end

  defp schedule_discovery do
    Process.send_after(self(), :discover_peers, 10_000)
  end
end

defmodule GossipNode.PeerConnectionManager do
  @moduledoc """
  The GossipNode PeerConnectionManager module.
  Manages active peer connection lifecycles, heartbeats, and pruning inactive peers.
  """
  use GenServer

  alias GossipNode.PeerRegistry
  alias GossipNode.Protocol

  @spec start_link(list()) :: {:ok, pid()} | {:error, term()}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{last_ping: %{}}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_heartbeat()
    {:ok, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    now = System.system_time(:second)
    ping_msg = %{type: :ping, sender: self(), timestamp: now}

    case Protocol.validate_msg(ping_msg) do
      {:ok, valid_ping} ->
        Enum.each(PeerRegistry.list_peers(), fn peer ->
          if is_pid(peer) and Process.alive?(peer) do
            send(peer, {:gossip_msg, valid_ping})
          else
            PeerRegistry.remove_peer(peer)
          end
        end)

      _ ->
        :ok
    end

    schedule_heartbeat()
    {:noreply, state}
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, 5000)
  end
end

defmodule GossipNode.PeerSampling do
  @moduledoc """
  The GossipNode PeerSampling module.
  Implements random peer sampling for epidemic routing stability.
  """
  use GenServer

  alias GossipNode.PeerRegistry

  @spec start_link(list()) :: {:ok, pid()} | {:error, term()}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{sample_size: 5}, name: __MODULE__)
  end

  @doc """
  Requests a random sample of registered active peers.
  """
  @spec get_sample() :: list(pid())
  def get_sample do
    GenServer.call(__MODULE__, :get_sample)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call(:get_sample, _from, state) do
    sample = PeerRegistry.list_peers() |> Enum.take_random(state.sample_size)
    {:reply, sample, state}
  end
end
