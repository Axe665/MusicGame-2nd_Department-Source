class_name HitSfx
extends Node

## Shared hit-sound pool for editor playback and playtest.

const VOLUME_DB := -7.0
const PATHS := {
	"don": "res://audio/sfx/tap_don.wav",
	"kat": "res://audio/sfx/tap_kat.wav",
	"bell": "res://audio/sfx/bell.wav",
	"trace": "res://audio/sfx/trace.wav",
	"tail": "res://audio/sfx/path_tail.wav",
}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _index: int = 0


func _ready() -> void:
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, "SFX")
		AudioServer.set_bus_send(index, "Master")
	for key in PATHS:
		var stream: AudioStream = load(String(PATHS[key]))
		if stream != null:
			_streams[key] = stream
	for i in 10:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		player.volume_db = VOLUME_DB
		add_child(player)
		_players.append(player)


func play(kind: String, pitch: float = 1.0) -> void:
	var stream: AudioStream = _streams.get(kind)
	if stream == null or _players.is_empty():
		return
	var player := _players[_index % _players.size()]
	_index += 1
	player.stream = stream
	player.pitch_scale = pitch
	player.play()


static func kind_for_note(note: Note) -> String:
	return "kat" if note.width >= 70.0 and note.width < 85.0 else "don"
