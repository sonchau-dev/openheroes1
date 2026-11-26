extends Node

## Autoload `Net`: the remote-play session.
##
## HOMM1's Network/Modem/Direct Connect modes all carried one protocol: at each
## turn boundary the whole run was written to a save file (REMOTE.GAM) and
## mailed down the link (KB homm1-native-data.md §5.1). We keep that protocol
## and replace only the dead transports (NetBIOS, dial-up, null-modem) with
## ENet over IP.
##
## Exactly one machine simulates at a time, so there is no lockstep, no
## rollback and no server authority: the sender's state IS the truth.
##
## Invariant that keeps fog honest: on every machine
## `GameState.active_player_side` always equals THIS machine's side, so all the
## existing side-relative rendering works untouched. Whose turn it actually is
## lives here, in `turn_side`.

signal link_established
signal link_failed(reason: String)
signal link_lost
signal status_changed(lines: PackedStringArray)

enum Role { NONE, HOST, GUEST }

const DEFAULT_PORT := 26999
const HOST_SIDE := 0
const GUEST_SIDE := 1

var role: int = Role.NONE
## Which world side this machine plays. -1 when no session is running.
var local_side: int = -1
## Which world side is actually taking its turn right now, across both machines.
var turn_side: int = -1
var link_up: bool = false
var last_error: String = ""
## Game-over text carried by a final packet; the map consumes it on boot.
var pending_game_over: String = ""
## Set when the remote player drops mid-game: the map offers the original's
## "continue with a computer player filling in" prompt.
var pending_takeover_side: int = -1

## Scene-routing seam. Live sessions enter the adventure map as soon as a state
## lands; tests drive the same state machine with no scene to change to.
var route_to_map: bool = true

var _peer: ENetMultiplayerPeer = null
var _remote_id: int = 0
## Set once our closing packet is on the wire: the disconnect that follows is
## the session ending, not the other player dropping.
var _closing: bool = false
var _status: PackedStringArray = PackedStringArray()

func _process(_delta: float) -> void:
	# poll() can emit peer_disconnected synchronously, which tears the peer down
	# underneath us: the local keeps the object alive through its own call, and
	# the member is re-checked before it is touched again.
	var peer := _peer
	if peer == null:
		return
	peer.poll()
	if _peer == null:
		return
	if _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_on_disconnected()
		return
	while _peer != null and _peer.get_available_packet_count() > 0:
		_receive(_peer.get_packet())

# --- session lifecycle -------------------------------------------------------

func is_active() -> bool:
	return _peer != null and role != Role.NONE

## True while this machine must sit on the waiting banner with input frozen.
func is_waiting_for_remote() -> bool:
	return is_active() and link_up and turn_side >= 0 and turn_side != local_side

func remote_side() -> int:
	if local_side < 0:
		return -1
	return GUEST_SIDE if local_side == HOST_SIDE else HOST_SIDE

func status_lines() -> PackedStringArray:
	return _status

func host_game(port: int = DEFAULT_PORT) -> String:
	close()
	var peer := ENetMultiplayerPeer.new()
	# max_clients 1: the original allowed exactly one guest per network game.
	var err := peer.create_server(port, 1)
	if err != OK:
		last_error = "Network initialization failed (port %d)" % port
		return last_error
	_peer = peer
	role = Role.HOST
	local_side = HOST_SIDE
	turn_side = -1
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	_set_status(["Initializing network.", "", "Waiting On Guest."])
	return ""

func join_game(address: String, port: int = DEFAULT_PORT) -> String:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		last_error = "Network initialization failed (%s)" % address
		return last_error
	_peer = peer
	role = Role.GUEST
	local_side = GUEST_SIDE
	turn_side = -1
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	_set_status(["Initializing network.", "", "Waiting On Host."])
	return ""

func close() -> void:
	_drop_link()
	role = Role.NONE
	local_side = -1
	turn_side = -1
	pending_game_over = ""
	pending_takeover_side = -1
	_status = PackedStringArray()

func _on_peer_connected(id: int) -> void:
	_remote_id = id
	link_up = true
	_set_status(["Waiting for other remote player to set up game."] \
			if role == Role.GUEST else [""])
	link_established.emit()

func _on_peer_disconnected(_id: int) -> void:
	_on_disconnected()

## Tear the transport down and keep everything else: the closing packet ends
## the link but the run, the seat and the game-over text live on.
func _drop_link() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	_remote_id = 0
	link_up = false
	_closing = false

func _on_disconnected() -> void:
	if _peer == null:
		return
	# A FINAL packet lands in the same poll as the disconnect behind it; read it
	# before the drop handling throws the peer away.
	while _peer != null and _peer.get_available_packet_count() > 0:
		_receive(_peer.get_packet())
	if _peer == null:
		return
	if _closing:
		# The other side acknowledged our closing packet: the session is over.
		_drop_link()
		return
	var was_up := link_up
	_drop_link()
	if not was_up:
		# Never established: a failed dial, not a drop.
		role = Role.NONE
		local_side = -1
		turn_side = -1
		last_error = "The other player's computer is not responding."
		_set_status([last_error])
		link_failed.emit(last_error)
		return
	# Established then lost. HOMM1 dumps the run to PLYREXIT and offers to fill
	# the seat with a computer player (KB §5.3).
	if Game.state != null:
		var err: String = Game.save_game(SaveGame.PLYREXIT_SLOT, Game.autosave_dir)
		if err != "":
			push_warning("PLYREXIT save failed: %s" % err)
		pending_takeover_side = remote_side()
	_set_status(["The other player's computer is not responding."])
	link_lost.emit()

# --- transmit / receive ------------------------------------------------------

## Serialize the run and hand the turn to `next_turn_side`. `message` (with
## kind FINAL) carries the game-over text so both clients end on the same words.
## `close_after` ships the run and then ends the link the way FINAL does: a
## kingdom eliminated on its own machine hands the survivors their game and
## leaves; the remote sees the drop and carries on (PLYREXIT offers the seat).
func send_state(next_turn_side: int, kind: int = NetProtocol.KIND_STATE,
		message: String = "", close_after: bool = false) -> String:
	if _peer == null or not link_up:
		return "No remote player is connected"
	if Game.state == null:
		return "No game in progress"
	var env := Game.build_envelope("REMOTE")
	# The envelope's active side is the ONE piece of turn ownership on the wire.
	env["active_player_side"] = next_turn_side
	if kind == NetProtocol.KIND_FINAL:
		env["net_message"] = message
	var frame := NetProtocol.encode(env, kind)
	# Address the peer explicitly. TARGET_PEER_BROADCAST is silently dropped by
	# ENetMultiplayerPeer when it is driven as a raw PacketPeer rather than
	# through a MultiplayerAPI (verified on Godot 4.7.1: put_packet returns OK
	# and nothing arrives).
	_peer.set_target_peer(_remote_id)
	var err := _peer.put_packet(frame)
	if err != OK:
		last_error = "Error sending data."
		return last_error
	if kind == NetProtocol.KIND_FINAL or close_after:
		# The closing packet ends the session, so neither side's game-over screen
		# can bounce FINAL back. ENet drops in-flight data on an immediate
		# disconnect, even on the receiver, so the peer is kept until the packet
		# is acknowledged; _on_disconnected then drops it quietly.
		link_up = false
		_closing = true
		_peer.get_peer(_remote_id).peer_disconnect_later(0)
		return ""
	if kind == NetProtocol.KIND_STATE:
		turn_side = next_turn_side
	if is_waiting_for_remote():
		_set_status(["%s player turn." % _color_name(next_turn_side), "",
				"  Press 'CANCEL' to abort."])
	return ""

## Host only, once per match: ship the opening position so the guest can watch
## their own kingdom while the host takes the first turn ("Transmit Game
## Start"). Called from the adventure map rather than the setup screen because
## the second kingdom does not exist until the map has configured the scenario
## — transmitting earlier would send the guest a run with no seat for them.
func begin_hosted_game() -> String:
	if role != Role.HOST or turn_side >= 0:
		return ""
	return send_state(HOST_SIDE)

func _receive(frame: PackedByteArray) -> void:
	var decoded := NetProtocol.decode(frame)
	if decoded.has("error"):
		last_error = String(decoded["error"])
		push_warning("Dropped a remote packet: %s" % last_error)
		_set_status([last_error])
		return
	var kind := int(decoded["kind"])
	if kind == NetProtocol.KIND_STATE and turn_side >= 0 and turn_side == local_side:
		push_warning("Dropped a remote state packet during our own turn")
		return
	var env: Dictionary = decoded["envelope"]
	var invalid := SaveGame.validate(env)
	if invalid != "":
		last_error = "Error receiving data. (%s)" % invalid
		push_warning(last_error)
		_set_status([last_error])
		return
	apply_state(env, kind)

## Apply a received run and re-point it at OUR side. Separated from _receive so
## tests can drive it without a peer.
func apply_state(env: Dictionary, kind: int = NetProtocol.KIND_STATE) -> void:
	var final := kind == NetProtocol.KIND_FINAL
	if final:
		_drop_link()
	Game.load_from_envelope(env)
	turn_side = int(env.get("active_player_side", local_side))
	var player: PlayerState = Game.state.player_of(local_side) if Game.state != null else null
	if player != null and not final and turn_side == local_side:
		player.select_turn_start_hero()   # our turn starts with this packet
	# A finished run may hold our seat dead; the game-over screen still shows.
	if player == null or not (Game.activate_local_player(local_side) or final):
		# Our own kingdom is missing from the run we were sent. Nothing about
		# the rest of the apply is safe, and silently rendering the sender's
		# side would leak their map.
		last_error = "The remote game has no seat for this player."
		push_error(last_error)
		_set_status([last_error])
		if route_to_map:
			Game.to_menu()
		return
	pending_game_over = String(env.get("net_message", "")) if final else ""
	if is_waiting_for_remote():
		_set_status(["%s player turn." % _color_name(turn_side), "",
				"  Press 'CANCEL' to abort."])
	else:
		_set_status([])
	if route_to_map:
		Game.to_map()

# --- disconnect fallback -----------------------------------------------------

## Accept the original's offer: the departed player becomes a computer player
## and the match continues locally. Returns false if there is nothing to fill.
func fill_remote_with_ai() -> bool:
	var side := pending_takeover_side
	pending_takeover_side = -1
	if Game.state == null or side < 0:
		return false
	var player: PlayerState = Game.state.player_of(side)
	if player == null or player.is_ai:
		return false
	player.is_ai = true
	if player.ai_level <= 0:
		player.ai_level = 2
	turn_side = local_side
	close()
	return true

func takeover_prompt() -> String:
	var side := pending_takeover_side
	if side < 0:
		return ""
	return ("Player %d has been logged out of the game.  The current game has "
			+ "been saved as 'PLYREXIT'.  Do you wish to continue playing with "
			+ "a computer player filling in for player %d?") % [side + 1, side + 1]

# --- helpers -----------------------------------------------------------------

func _color_name(side: int) -> String:
	var names := ["Blue", "Green", "Red", "Yellow"]
	var player: PlayerState = Game.state.player_of(side) if Game.state != null else null
	if player == null:
		return "Other"
	return names[clampi(player.crest_idx / 4, 0, 3)]

func _set_status(lines: Array) -> void:
	_status = PackedStringArray(lines)
	status_changed.emit(_status)
