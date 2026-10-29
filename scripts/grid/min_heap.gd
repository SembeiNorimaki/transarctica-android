class_name MinHeap
extends RefCounted
# Binary min-heap of items ordered by a float priority. Equal priorities come out first-in first-out,
# so searches are deterministic.

var _prio := PackedFloat64Array()
var _seq := PackedInt64Array()
var _items: Array = []
var _counter := 0


func is_empty() -> bool:
    return _items.is_empty()

func size() -> int:
    return _items.size()

func clear() -> void:
    _prio.clear()
    _seq.clear()
    _items.clear()
    _counter = 0

func push(item: Variant, priority: float) -> void:
    _prio.append(priority)
    _seq.append(_counter)
    _items.append(item)
    _counter += 1
    _sift_up(_items.size() - 1)

func pop() -> Variant:
    assert(not _items.is_empty(), "MinHeap: pop on empty heap")
    var top: Variant = _items[0]
    var last := _items.size() - 1
    _swap(0, last)
    _prio.resize(last)
    _seq.resize(last)
    _items.resize(last)
    if last > 0:
        _sift_down(0)
    return top

func peek_priority() -> float:
    return _prio[0]


func _less(i: int, j: int) -> bool:
    if _prio[i] != _prio[j]:
        return _prio[i] < _prio[j]
    return _seq[i] < _seq[j]

func _swap(i: int, j: int) -> void:
    var p := _prio[i]; _prio[i] = _prio[j]; _prio[j] = p
    var s := _seq[i]; _seq[i] = _seq[j]; _seq[j] = s
    var t: Variant = _items[i]; _items[i] = _items[j]; _items[j] = t

func _sift_up(i: int) -> void:
    while i > 0:
        var parent := (i - 1) / 2
        if not _less(i, parent):
            return
        _swap(i, parent)
        i = parent

func _sift_down(i: int) -> void:
    var n := _items.size()
    while true:
        var l := 2 * i + 1
        var r := l + 1
        var smallest := i
        if l < n and _less(l, smallest):
            smallest = l
        if r < n and _less(r, smallest):
            smallest = r
        if smallest == i:
            return
        _swap(i, smallest)
        i = smallest
