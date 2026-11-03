class_name MediaIO
extends RefCounted

## Native Godot formats are used directly. Everything else is converted into
## the user cache with ffmpeg when it is available; the chart keeps the original
## path, so replacing or re-linking the source still works.

const NATIVE_AUDIO := ["wav", "ogg", "mp3"]
const NATIVE_VIDEO := ["ogv"]

## Executable used for every conversion. The editor keeps this in sync with its
## own setting so a bundled or non-PATH ffmpeg also works for audio analysis.
static var ffmpeg_exe: String = "ffmpeg"

static var _ffmpeg_checked := false
static var _ffmpeg_available := false
static var last_error: String = ""


static func set_ffmpeg_exe(path: String) -> void:
	var trimmed := path.strip_edges()
	ffmpeg_exe = trimmed if not trimmed.is_empty() else "ffmpeg"
	_ffmpeg_checked = false


static func has_ffmpeg() -> bool:
	if _ffmpeg_checked:
		return _ffmpeg_available
	_ffmpeg_checked = true
	var output: Array = []
	var code := OS.execute(ffmpeg_exe, ["-version"], output, true, false)
	_ffmpeg_available = code == 0
	return _ffmpeg_available


static func is_native_audio(path: String) -> bool:
	return path.get_extension().to_lower() in NATIVE_AUDIO


static func is_native_video(path: String) -> bool:
	return path.get_extension().to_lower() in NATIVE_VIDEO


static func prepare_audio(path: String) -> String:
	last_error = ""
	if path.is_empty():
		return ""
	if is_native_audio(path):
		return path
	var source := _source_path(path)
	var target := _cache_path(path, "ogg")
	if FileAccess.file_exists(target):
		return target
	if not has_ffmpeg():
		last_error = "该音频格式需要 ffmpeg；当前 PATH 中找不到 ffmpeg。"
		return ""
	DirAccess.make_dir_recursive_absolute("user://media")
	var args := [
		"-y", "-i", source, "-vn", "-acodec", "libvorbis", "-q:a", "5",
		ProjectSettings.globalize_path(target),
	]
	var output: Array = []
	var code := OS.execute(ffmpeg_exe, args, output, true, false)
	if code != 0 or not FileAccess.file_exists(target):
		last_error = "音频转换失败：%s" % path.get_file()
		return ""
	return target


static func prepare_video(path: String) -> String:
	last_error = ""
	if path.is_empty():
		return ""
	if is_native_video(path):
		return path
	var source := _source_path(path)
	var target := _cache_path(path, "ogv")
	if FileAccess.file_exists(target):
		return target
	if not has_ffmpeg():
		last_error = "该视频格式需要 ffmpeg；当前 PATH 中找不到 ffmpeg。"
		return ""
	DirAccess.make_dir_recursive_absolute("user://media")
	var args := [
		"-y", "-i", source,
		"-c:v", "libtheora", "-q:v", "7", "-an", "-pix_fmt", "yuv420p",
		ProjectSettings.globalize_path(target),
	]
	var output: Array = []
	var code := OS.execute(ffmpeg_exe, args, output, true, false)
	if code != 0 or not FileAccess.file_exists(target):
		last_error = "视频转换失败：%s" % path.get_file()
		return ""
	return target


static func _source_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


static func _cache_path(path: String, extension: String) -> String:
	var stem := path.get_file().get_basename().validate_filename()
	var digest := path.md5_text().substr(0, 10)
	return "user://media/%s_%s.%s" % [stem, digest, extension]
