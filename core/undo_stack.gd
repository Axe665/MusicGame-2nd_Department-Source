class_name UndoStack
extends RefCounted

const LIMIT := 200

var undo_items: Array[Dictionary] = []
var redo_items: Array[Dictionary] = []


func clear() -> void:
	undo_items.clear()
	redo_items.clear()


func record(snapshot: Dictionary) -> void:
	undo_items.append(snapshot)
	if undo_items.size() > LIMIT:
		undo_items.pop_front()
	redo_items.clear()


func can_undo() -> bool:
	return not undo_items.is_empty()


func can_redo() -> bool:
	return not redo_items.is_empty()


func undo(current: Dictionary) -> Dictionary:
	if undo_items.is_empty():
		return current
	redo_items.append(current)
	return undo_items.pop_back()


func redo(current: Dictionary) -> Dictionary:
	if redo_items.is_empty():
		return current
	undo_items.append(current)
	return redo_items.pop_back()
