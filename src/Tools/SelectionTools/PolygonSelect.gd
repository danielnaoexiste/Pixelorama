extends SelectionTool

var _last_position := Vector2.INF
var _draw_points := []
var _ready_to_apply := false


func _input(event: InputEvent) -> void:
	._input(event)
	if _move:
		return
	if event is InputEventMouseMotion:
		_last_position = Global.canvas.current_pixel.floor()
	elif event is InputEventMouseButton:
		if event.doubleclick and event.button_index == tool_slot.button and _draw_points:
			$DoubleClickTimer.start()
			append_gap(_draw_points[-1], _draw_points[0], _draw_points)
			_ready_to_apply = true
			apply_selection(Vector2.ZERO)  # Argument doesn't matter
	elif event is InputEventKey:
		if event.is_action_pressed("escape") and _ongoing_selection:
			_ongoing_selection = false
			_draw_points.clear()
			_ready_to_apply = false
			Global.canvas.previews.update()


func draw_start(position: Vector2) -> void:
	if !$DoubleClickTimer.is_stopped():
		return
	.draw_start(position)
	if !_move and !_draw_points:
		_ongoing_selection = true
		_draw_points.append(position)
		_last_position = position


func draw_move(position: Vector2) -> void:
	if selection_node.arrow_key_move:
		return
	.draw_move(position)


func draw_end(position: Vector2) -> void:
	if selection_node.arrow_key_move:
		return
	if !_move and _draw_points:
		append_gap(_draw_points[-1], position, _draw_points)
		if position == _draw_points[0] and _draw_points.size() > 1:
			_ready_to_apply = true

	.draw_end(position)


func draw_preview() -> void:
	if _ongoing_selection and !_move:
		var canvas: Node2D = Global.canvas.previews
		var position := canvas.position
		var scale := canvas.scale
		if Global.mirror_view:
			position.x = position.x + Global.current_project.size.x
			scale.x = -1

		var preview_draw_points := _draw_points.duplicate()
		append_gap(_draw_points[-1], _last_position, preview_draw_points)

		canvas.draw_set_transform(position, canvas.rotation, scale)
		var indicator := _fill_bitmap_with_points(preview_draw_points, Global.current_project.size)

		for line in _create_polylines(indicator):
			canvas.draw_polyline(PoolVector2Array(line), Color.black)

		var circle_radius: Vector2 = Global.camera.zoom * 10
		circle_radius.x = clamp(circle_radius.x, 2, circle_radius.x)
		circle_radius.y = clamp(circle_radius.y, 2, circle_radius.y)

		if _last_position == _draw_points[0] and _draw_points.size() > 1:
			draw_empty_circle(
				canvas, _draw_points[0] + Vector2.ONE * 0.5, circle_radius, Color.black
			)

		# Handle mirroring
		if tool_slot.horizontal_mirror:
			for line in _create_polylines(
				_fill_bitmap_with_points(
					mirror_array(preview_draw_points, true, false), Global.current_project.size
				)
			):
				canvas.draw_polyline(PoolVector2Array(line), Color.black)
			if tool_slot.vertical_mirror:
				for line in _create_polylines(
					_fill_bitmap_with_points(
						mirror_array(preview_draw_points, true, true), Global.current_project.size
					)
				):
					canvas.draw_polyline(PoolVector2Array(line), Color.black)
		if tool_slot.vertical_mirror:
			for line in _create_polylines(
				_fill_bitmap_with_points(
					mirror_array(preview_draw_points, false, true), Global.current_project.size
				)
			):
				canvas.draw_polyline(PoolVector2Array(line), Color.black)

		canvas.draw_set_transform(canvas.position, canvas.rotation, canvas.scale)


func apply_selection(_position) -> void:
	if !_ready_to_apply:
		return
	var project: Project = Global.current_project
	var cleared := false
	if !_add and !_subtract and !_intersect:
		cleared = true
		Global.canvas.selection.clear_selection()
	if _draw_points.size() > 3:
		var selection_bitmap_copy: BitMap = project.selection_bitmap.duplicate()
		var bitmap_size: Vector2 = selection_bitmap_copy.get_size()
		if _intersect:
			selection_bitmap_copy.set_bit_rect(Rect2(Vector2.ZERO, bitmap_size), false)
		lasso_selection(selection_bitmap_copy, _draw_points)

		# Handle mirroring
		if tool_slot.horizontal_mirror:
			lasso_selection(selection_bitmap_copy, mirror_array(_draw_points, true, false))
			if tool_slot.vertical_mirror:
				lasso_selection(selection_bitmap_copy, mirror_array(_draw_points, true, true))
		if tool_slot.vertical_mirror:
			lasso_selection(selection_bitmap_copy, mirror_array(_draw_points, false, true))

		project.selection_bitmap = selection_bitmap_copy
		Global.canvas.selection.big_bounding_rectangle = project.get_selection_rectangle(
			project.selection_bitmap
		)
	else:
		if !cleared:
			Global.canvas.selection.clear_selection()

	Global.canvas.selection.commit_undo("Select", undo_data)
	_ongoing_selection = false
	_draw_points.clear()
	_ready_to_apply = false
	Global.canvas.previews.update()


func lasso_selection(bitmap: BitMap, points: PoolVector2Array) -> void:
	var project: Project = Global.current_project
	var size := bitmap.get_size()
	for point in points:
		if point.x < 0 or point.y < 0 or point.x >= size.x or point.y >= size.y:
			continue
		if _intersect:
			if project.selection_bitmap.get_bit(point):
				bitmap.set_bit(point, true)
		else:
			bitmap.set_bit(point, !_subtract)

	var v := Vector2()
	var image_size: Vector2 = project.size
	for x in image_size.x:
		v.x = x
		for y in image_size.y:
			v.y = y
			if Geometry.is_point_in_polygon(v, points):
				if _intersect:
					if project.selection_bitmap.get_bit(v):
						bitmap.set_bit(v, true)
				else:
					bitmap.set_bit(v, !_subtract)


# Bresenham's Algorithm
# Thanks to https://godotengine.org/qa/35276/tile-based-line-drawing-algorithm-efficiency
func append_gap(start: Vector2, end: Vector2, array: Array) -> void:
	var dx := int(abs(end.x - start.x))
	var dy := int(-abs(end.y - start.y))
	var err := dx + dy
	var e2 := err << 1
	var sx = 1 if start.x < end.x else -1
	var sy = 1 if start.y < end.y else -1
	var x = start.x
	var y = start.y
	while !(x == end.x && y == end.y):
		e2 = err << 1
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
		array.append(Vector2(x, y))


func _fill_bitmap_with_points(points: Array, size: Vector2) -> BitMap:
	var bitmap := BitMap.new()
	bitmap.create(size)

	for point in points:
		if point.x < 0 or point.y < 0 or point.x >= size.x or point.y >= size.y:
			continue
		bitmap.set_bit(point, 1)

	return bitmap


func mirror_array(array: Array, h: bool, v: bool) -> Array:
	var new_array := []
	var project: Project = Global.current_project
	for point in array:
		if h and v:
			new_array.append(
				Vector2(project.x_symmetry_point - point.x, project.y_symmetry_point - point.y)
			)
		elif h:
			new_array.append(Vector2(project.x_symmetry_point - point.x, point.y))
		elif v:
			new_array.append(Vector2(point.x, project.y_symmetry_point - point.y))

	return new_array


# Thanks to
# https://www.reddit.com/r/godot/comments/3ktq39/drawing_empty_circles_and_curves/cv0f4eo/
func draw_empty_circle(
	canvas: CanvasItem, circle_center: Vector2, circle_radius: Vector2, color: Color
) -> void:
	var draw_counter := 1
	var line_origin := Vector2()
	var line_end := Vector2()
	line_origin = circle_radius + circle_center

	while draw_counter <= 360:
		line_end = circle_radius.rotated(deg2rad(draw_counter)) + circle_center
		canvas.draw_line(line_origin, line_end, color)
		draw_counter += 1
		line_origin = line_end

	line_end = circle_radius.rotated(deg2rad(360)) + circle_center
	canvas.draw_line(line_origin, line_end, color)
