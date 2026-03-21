extends Node2D

func _ready() -> void:
    _process(0)

func _process(_delta: float) -> void:
    for child in get_children():
        if child is GrappleLine2D:
            var line:GrappleLine2D = child
            var player := Globals.player_ref
            if Globals.player_ref != null:
                line.end_point = player.grapple_point.position - player.position
            line.update_points()
