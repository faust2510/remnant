class_name SpatialGrid
extends RefCounted
## 静态链表式均匀网格空间哈希。
## cell_head / entity_next 用 PackedInt32Array 实现，每帧只 fill，不分配内存。

const HASH_SIZE := 4096  # 2 的幂，抗碰撞靠坐标二次校验

var cell_size: float = 32.0
var inv_cell: float = 1.0 / 32.0
var cell_head: PackedInt32Array = PackedInt32Array()
var entity_next: PackedInt32Array = PackedInt32Array()
var ex: PackedFloat32Array = PackedFloat32Array()
var ey: PackedFloat32Array = PackedFloat32Array()
var count: int = 0

func setup(max_entities: int, _cell_size: float) -> void:
	cell_size = _cell_size
	inv_cell = 1.0 / _cell_size
	cell_head.resize(HASH_SIZE)
	cell_head.fill(-1)
	entity_next.resize(max_entities)

func hash_cell(cx: int, cy: int) -> int:
	var h: int = (cx * 73856093) ^ (cy * 19349663)
	return h & (HASH_SIZE - 1)

func rebuild(px: PackedFloat32Array, py: PackedFloat32Array, n: int) -> void:
	ex = px
	ey = py
	count = n
	cell_head.fill(-1)
	for i in range(n):
		var cx: int = int(floor(px[i] * inv_cell))
		var cy: int = int(floor(py[i] * inv_cell))
		var h: int = hash_cell(cx, cy)
		entity_next[i] = cell_head[h]
		cell_head[h] = i

## 半径内的实体索引写入 out，返回写入数量（out 由调用方预分配）。
func query_radius(x: float, y: float, radius: float, out: PackedInt32Array, max_out: int) -> int:
	var n: int = 0
	var r2: float = radius * radius
	var min_cx: int = int(floor((x - radius) * inv_cell))
	var max_cx: int = int(floor((x + radius) * inv_cell))
	var min_cy: int = int(floor((y - radius) * inv_cell))
	var max_cy: int = int(floor((y + radius) * inv_cell))
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			var h: int = hash_cell(cx, cy)
			var i: int = cell_head[h]
			while i != -1:
				# 哈希碰撞校验：真正落在该格才收
				var icx: int = int(floor(ex[i] * inv_cell))
				var icy: int = int(floor(ey[i] * inv_cell))
				if icx == cx and icy == cy:
					var dx: float = ex[i] - x
					var dy: float = ey[i] - y
					if dx * dx + dy * dy <= r2:
						if n < max_out:
							out[n] = i
							n += 1
				i = entity_next[i]
	return n
