extends Node
## Session layer: host / join / solo, the crew roster, and LAN discovery.
## Gameplay RPCs live on the Game node (fixed path /root/Main/Game).

signal roster_changed
signal joined_ok
signal join_failed(reason: String)
signal session_ended(reason: String)

const PORT := 24680
const DISCOVERY_PORT := 24681
const MAX_CREW := 8
const PROTOCOL := 1

var players := {}          # peer_id -> {name, color, hat}
var hosting := false
var lan_hosts := {}        # "ip:port" -> {name, crew, seen}

var _beacon: PacketPeerUDP
var _listener: PacketPeerUDP
var _beacon_t := 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: join_failed.emit("Couldn't reach that host."))
	multiplayer.server_disconnected.connect(func() -> void:
		_reset()
		session_ended.emit("The host left. The Mossback wanders on without you."))

func my_info() -> Dictionary:
	return {"name": G.player_name, "color": G.player_color_idx, "hat": G.player_hat, "v": PROTOCOL}

func start_solo() -> void:
	_reset()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players[1] = my_info()
	hosting = true
	roster_changed.emit()

func host(port := PORT) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CREW)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players[1] = my_info()
	hosting = true
	_start_beacon()
	roster_changed.emit()
	return OK

func join(address: String, port := PORT) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK

func leave() -> void:
	_reset()

func _reset() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	hosting = false
	if _beacon:
		_beacon.close()
		_beacon = null

func is_server() -> bool:
	return multiplayer.is_server()

func my_id() -> int:
	return multiplayer.get_unique_id()

func _on_connected() -> void:
	_register.rpc_id(1, my_info())

func _on_peer_connected(_id: int) -> void:
	pass

func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players.erase(id)
		if is_server():
			_roster.rpc(players)
		roster_changed.emit()

@rpc("any_peer", "reliable")
func _register(info: Dictionary) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if int(info.get("v", 0)) != PROTOCOL:
		_rejected.rpc_id(id, "Version mismatch with the host.")
		return
	# keep crew colours unique when possible
	var used := []
	for pid in players:
		if pid != id:
			used.append(players[pid].color)
	var c := int(info.get("color", 0))
	var tries := 0
	while c in used and tries < G.CREW_COLORS.size():
		c = (c + 1) % G.CREW_COLORS.size()
		tries += 1
	info.color = c
	info.name = String(info.get("name", "Tender")).left(16)
	players[id] = info
	_roster.rpc(players)
	roster_changed.emit()

@rpc("authority", "reliable")
func _roster(p: Dictionary) -> void:
	var first := not players.has(my_id())
	players = p
	roster_changed.emit()
	if first and players.has(my_id()):
		joined_ok.emit()

@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	_reset()
	join_failed.emit(reason)

func update_my_look() -> void:
	if players.has(my_id()):
		players[my_id()] = my_info()
		if is_server():
			_roster.rpc(players)
			roster_changed.emit()
		else:
			_register.rpc_id(1, my_info())

# ---------------------------------------------------------------- LAN discovery
func _start_beacon() -> void:
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)

func listen_lan(on: bool) -> void:
	if on and _listener == null:
		_listener = PacketPeerUDP.new()
		if _listener.bind(DISCOVERY_PORT) != OK:
			_listener = null
	elif not on and _listener:
		_listener.close()
		_listener = null
		lan_hosts.clear()

func _process(dt: float) -> void:
	if _beacon and hosting:
		_beacon_t -= dt
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			var msg := "MOSSBACK|%d|%s|%d" % [PROTOCOL, G.player_name, players.size()]
			_beacon.put_packet(msg.to_utf8_buffer())
	if _listener:
		while _listener.get_available_packet_count() > 0:
			var pkt := _listener.get_packet().get_string_from_utf8()
			var ip := _listener.get_packet_ip()
			var parts := pkt.split("|")
			if parts.size() >= 4 and parts[0] == "MOSSBACK":
				lan_hosts[ip] = {"name": parts[2], "crew": int(parts[3]), "seen": Time.get_ticks_msec()}
		for k in lan_hosts.keys():
			if Time.get_ticks_msec() - lan_hosts[k].seen > 4000:
				lan_hosts.erase(k)
