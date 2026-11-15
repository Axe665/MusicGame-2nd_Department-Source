class_name HitSfx
extends Node

## Shared hit-sound pool for editor playback and playtest.

const VOLUME_DB := -3.0
const KIND_DB := {"don": -3.0, "kat": -3.5, "hold_end": -4.0, "path": -3.5, "anchor": -2.0, "bell": -4.0, "tail": -3.5, "slide": 0.0}
const STYLE_PITCH := {"default": 1.0, "crisp": 1.18, "deep": 0.84}
const STYLE_DB := {"default": 0.0, "crisp": -1.0, "deep": 1.5}
const PATHS := {
	"don": "res://audio/sfx/tap_don.ogg",
	"hold_end": "res://audio/sfx/hold_end.ogg",
	"path": "res://audio/sfx/path.wav",
	"anchor": "res://audio/sfx/anchor.wav",
	"kat": "res://audio/sfx/tap_kat.wav",
	"bell": "res://audio/sfx/bell.ogg",
	"tail": "res://audio/sfx/path_tail.wav",
	# 星星可以开始划的提示音（比 path 头音更高更亮）。
	"slide": "res://audio/sfx/slide.wav",
}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _index: int = 0
var style: String = "default"


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


func set_style(value: String) -> void:
	style = value


func play(kind: String, pitch: float = 1.0) -> void:
	if style == "mute":
		return
	var stream: AudioStream = _streams.get(kind)
	if stream == null or _players.is_empty():
		return
	var player := _players[_index % _players.size()]
	_index += 1
	player.stream = stream
	player.volume_db = float(KIND_DB.get(kind, VOLUME_DB)) + float(STYLE_DB.get(style, 0.0))
	player.pitch_scale = pitch * float(STYLE_PITCH.get(style, 1.0))
	player.play()


static func kind_for_note(note: Note) -> String:
	return "kat" if note.width >= 70.0 and note.width < 85.0 else "don"
