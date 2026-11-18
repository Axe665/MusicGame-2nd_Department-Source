class_name UndoStack
extends RefCounted

const LIMIT := 200
## 快照内存由音符数主导：200 份 1 万音符的谱面 ≈1GB。
## 这里按「所有快照里的音符总数」限额，10k 谱约保留 12 步，小谱仍是 200 步。
const NOTE_BUDGET := 120000

var undo_items: Array[Dictionary] = []
var redo_items: Array[Dictionary] = []
var _undo_notes := 0


func clear() -> void:
	undo_items.clear()
	redo_items.clear()
	_undo_notes = 0


func _weight(snapshot: Dictionary) -> int:
	var notes: Variant = snapshot.get("notes", [])
	return notes.size() if notes is Array else 0


func record(snapshot: Dictionary) -> void:
	undo_items.append(snapshot)
	_undo_notes += _weight(snapshot)
	while undo_items.size() > 1 and (undo_items.size() > LIMIT or _undo_notes > NOTE_BUDGET):
		_undo_notes -= _weight(undo_items.pop_front())
	redo_items.clear()


func can_undo() -> bool:
	return not undo_items.is_empty()


func can_redo() -> bool:
	return not redo_items.is_empty()


func undo(current: Dictionary) -> Dictionary:
	if undo_items.is_empty():
		return current
	redo_items.append(current)
	var item: Dictionary = undo_items.pop_back()
	_undo_notes -= _weight(item)
	return item


func redo(current: Dictionary) -> Dictionary:
	if redo_items.is_empty():
		return current
	undo_items.append(current)
	_undo_notes += _weight(current)
	return redo_items.pop_back()
