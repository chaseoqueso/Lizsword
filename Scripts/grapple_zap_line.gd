class_name GrappleLine2D
extends Line2D

@export var start_point: Vector2
@export var end_point: Vector2
@export var num_points: int = 10
@export var relative_width_range: float = 1
@export var max_width_range: float = 3

func _ready() -> void:
    start_point = Vector2.ZERO
    var temp := points
    for i in range(num_points):
        temp.append(Vector2.ZERO)
    points = temp
    update_points()

func update_points() -> void:
    if points.size() != 0:
        points[0] = start_point
        points[points.size()-1] = end_point

        var prev_x_offset := 0.0
        for i in range(1, num_points - 1):
            # weights the width range so that the range is smaller near the endpoints
            var limited_width_range := max_width_range * sqrt(1 - (2 * abs(i - num_points/2.0) / num_points))

            var min_y_offset:float = max(-limited_width_range, prev_x_offset - relative_width_range)
            var max_y_offset:float = min(limited_width_range, prev_x_offset + relative_width_range)
            var x_offset := end_point.length()/(2 * num_points)
        
            var center:Vector2 = lerp(start_point, end_point, i/(float)(num_points - 1))
            var offset := Vector2(randf_range(-x_offset, x_offset), randf_range(min_y_offset, max_y_offset))
            prev_x_offset = offset.x
            offset = offset.rotated(end_point.angle())

            points[i] = center + offset
