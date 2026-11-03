class_name GridDivisions
extends RefCounted

## Beat-grid divisions used by the chart canvas and the snap setting.
##
## The list mirrors the Malody 4.3.7 editor's right-hand "beat split" column:
## 1/2, 1/3, 1/4, 1/6, 1/8, 1/12, 1/16, 1/24, 1/32. The number is the count of
## cells per beat, so 1/4 means four cells per beat (sixteenth notes in 4/4).
##
## Triplets (1/3, 1/6, 1/12, 1/24) and the plain powers of two live in the same
## list on purpose: one integer is enough to describe both the grid lines and
## the snap step, which keeps the canvas column, the toolbar dropdown and the
## inspector in sync without a triplet/quint flag pair.

const ITEMS: Array[int] = [2, 3, 4, 6, 8, 12, 16, 24, 32]
const LABELS: Array[String] = ["1/2", "1/3", "1/4", "1/6", "1/8", "1/12", "1/16", "1/24", "1/32"]
const DEFAULT_DIVISION := 4


static func normalize(division: int) -> int:
	if ITEMS.has(division):
		return division
	return DEFAULT_DIVISION


static func index_of(division: int) -> int:
	var index := ITEMS.find(normalize(division))
	return index if index >= 0 else ITEMS.find(DEFAULT_DIVISION)


static func label(division: int) -> String:
	return LABELS[index_of(division)]


static func step_beats(division: int) -> float:
	return 1.0 / float(normalize(division))


static func snap(beat: float, division: int, bypass: bool = false) -> float:
	if bypass:
		return beat
	var step := step_beats(division)
	return roundf(beat / step) * step
