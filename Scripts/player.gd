extends CharacterBody2D

@export_group("Movement")
@export var max_speed: float = 100
@export var accel: float = 500

@export_group("Aerial Movement")
@export var air_accel: float = 500
@export var gravity: float = 200
@export var jump_velocity: float = 100

@export_group("Climbing")
@export var climb_speed: float = 100
@export var wall_jump_velocity: float = 100
@export var wall_jump_angle: float = 45
@export var ceil_jump_velocity: float = 100

@export_group("Charge Attack")
@export var charge_time: float = 1
@export var min_launch_velocity: float = 200
@export var max_launch_velocity: float = 500
@export var final_bounce_velocity: float = 200
@export var max_air_charge_velocity: float = 50

enum PlayerState { IDLE, RUNNING, CHARGING, LAUNCHING, WALL_CLIMB, CEIL_CLIMB }

var current_state: PlayerState
var initial_gravity: float
var remaining_bounces: int
var current_charge: float
var wall_normal: Vector2

func _ready() -> void:
	initial_gravity = gravity
	current_state = PlayerState.IDLE
	remaining_bounces = 0
	current_charge = 0

func _process(delta: float) -> void:
	var inputX := Input.get_action_strength("right") - Input.get_action_strength("left")

	# Animation Selection
	$AnimatedSprite2D.rotation = 0
	var reset_flip_v := true
	var should_flip_h := false

	if current_state == PlayerState.CHARGING:
		if current_charge < 1:
			$AnimatedSprite2D.play("charge")
		else:
			$AnimatedSprite2D.play("chargeMax")
		reset_flip_v = false
		$AnimatedSprite2D.flip_h = get_local_mouse_position().x < 0
	elif current_state == PlayerState.LAUNCHING:
		$AnimatedSprite2D.play("launch")
		$AnimatedSprite2D.rotation = Vector2.UP.angle_to(velocity)
	elif current_state == PlayerState.WALL_CLIMB:
		$AnimatedSprite2D.play("climb")
		$AnimatedSprite2D.flip_h = get_wall_normal().x < 0
	elif current_state == PlayerState.CEIL_CLIMB:
		$AnimatedSprite2D.play("stance")
		$AnimatedSprite2D.flip_v = true
		reset_flip_v = false
		should_flip_h = true
	else:
		if is_on_floor():
			if inputX != 0:
				$AnimatedSprite2D.play("run")
				change_state(PlayerState.RUNNING)
			else:
				$AnimatedSprite2D.play("idle")
				change_state(PlayerState.IDLE)
		else: # Midair
			if velocity.y < 0:
				$AnimatedSprite2D.play("jump")
			else:
				$AnimatedSprite2D.play("fall")
		should_flip_h = true

	if should_flip_h and inputX != 0:
		$AnimatedSprite2D.flip_h = inputX < 0

	if reset_flip_v:
		$AnimatedSprite2D.flip_v = false


func _physics_process(delta: float) -> void:
	#############################
	### Velocity Calculations ###
	#############################

	var inputX := Input.get_action_strength("right") - Input.get_action_strength("left")
	var inputY := Input.get_action_strength("up") - Input.get_action_strength("down")
	var current_accel := accel if is_on_floor() else air_accel 

	var apply_friction := func():
		velocity.x -= sign(velocity.x) * current_accel * delta
		if abs(velocity.x) <= current_accel * delta:
			velocity.x = 0

	var apply_gravity := func(g = gravity):
		velocity.y += g * delta

	if current_state == PlayerState.CHARGING:
		# Charge up
		current_charge += delta / charge_time
		if current_charge > 1:
			current_charge = 1
		
		if is_on_floor():
			apply_friction.call()
		else:
			# Apply a slow-mo effect to the player's movement by decreasing
			# air resistance and gravity

			apply_gravity.call(gravity / 2)

			# current_accel = air_accel/5

			# # Instead of the velocity decreasing all the way to 0, we have a minimum value
			# if velocity.x > max_air_charge_velocity:
			# 	apply_friction.call()
			# else:
			# 	velocity.x = sign(velocity.x) * max_air_charge_velocity

	elif is_climbing():
		# Always allow movement in all directions while climbing,
		# worst case the player just falls off the wall
		velocity.x = inputX * climb_speed
		velocity.y = -inputY * climb_speed

		# Apply a small velocity in the direction of the wall/ceiling
		# to keep sticking to it, if not pressing perpendicular movement
		if inputX == 0 and current_state == PlayerState.WALL_CLIMB:
			velocity.x = -wall_normal.x
		elif inputY == 0 and current_state == PlayerState.CEIL_CLIMB:
			velocity.y = -1
		print(velocity)
			
	elif current_state != PlayerState.LAUNCHING:
		# Apply gravity
		apply_gravity.call()

		# Handle movement input
		if inputX == 0 and is_on_floor():
			apply_friction.call()
		else:
			velocity.x += inputX * current_accel * delta
			if abs(velocity.x) > max_speed:
				velocity.x = sign(velocity.x) * max_speed

	##########################################
	### Apply Velocity & Handle Collisions ###
	##########################################

	# Move the player
	if current_state != PlayerState.LAUNCHING:
		# print(str(current_state) + " " + str(velocity))
		move_and_slide()
		if is_climbing() and not(is_on_wall() or is_on_ceiling()):
			change_state(PlayerState.IDLE)
			wall_normal = Vector2.ZERO
		elif is_on_wall() and inputX == -get_wall_normal().x:
			change_state(PlayerState.WALL_CLIMB)
		elif is_on_ceiling() and inputY == -1:
			change_state(PlayerState.CEIL_CLIMB)
			wall_normal = Vector2.ZERO
	else: # Launching
		var collision := move_and_collide(velocity * delta)
		if collision:
			var tilemap: TileMapLayer = collision.get_collider()

			# Attempt to find the tile inward based on collision normal
			var tile_position := collision.get_position() - collision.get_normal()
			var cell_pos := tilemap.local_to_map(tilemap.to_local(tile_position))
			var data := tilemap.get_cell_tile_data(cell_pos)
			print("Tile from normal: " + str(tile_position))
			# If no tile was found, attempt to find the tile inward based on velocity direction
			if data == null:
				tile_position = collision.get_position() + velocity.normalized()
				cell_pos = tilemap.local_to_map(tilemap.to_local(tile_position))
				data = tilemap.get_cell_tile_data(cell_pos)
				print("Tile from velocity: " + str(tile_position))

			if data != null:
				if data.get_collision_polygons_count(1) > 0:
					velocity = velocity.bounce(collision.get_normal())
					remaining_bounces -= 1

					if remaining_bounces <= 0:
						change_state(PlayerState.IDLE)
						velocity = velocity.normalized() * final_bounce_velocity
				else:
					if collision.get_normal().x != 0:
						velocity = -collision.get_normal()
						move_and_slide()
						change_state(PlayerState.WALL_CLIMB)
					else:
						change_state(PlayerState.CEIL_CLIMB)


func _input(event):
	if event.is_action_pressed("attack"):
		# PlayerGlobals.is_attacking = true
		change_state(PlayerState.CHARGING)
	elif event.is_action_released("attack") and current_state == PlayerState.CHARGING:     # If we are in the charge state but attack is not pressed, launch
		velocity = get_local_mouse_position().normalized() * lerpf(min_launch_velocity, max_launch_velocity, current_charge)
		current_charge = 0
		remaining_bounces = 3
		change_state(PlayerState.LAUNCHING)

	if event.is_action_pressed("jump") and (is_on_floor() or is_climbing()):
		if current_state == PlayerState.WALL_CLIMB:
			velocity = Vector2.from_angle(-wall_jump_angle) * wall_jump_velocity
			velocity.x *= get_wall_normal().x 
		elif is_on_floor():
			velocity.y = -jump_velocity
		elif current_state == PlayerState.CEIL_CLIMB:
			velocity.y = ceil_jump_velocity

		$AnimatedSprite2D.play("jump")
		change_state(PlayerState.IDLE)

func change_state(new_state: PlayerState):
	if current_state == new_state:
		return
	current_state = new_state
	
	if new_state == PlayerState.WALL_CLIMB:
		wall_normal = get_wall_normal()
	elif new_state == PlayerState.CHARGING:
		if not is_on_floor():
			velocity *= 0.5

# func _on_animated_sprite_2d_animation_finished() -> void:
#     PlayerGlobals.is_attacking = false

func is_climbing():
	return current_state == PlayerState.WALL_CLIMB or current_state == PlayerState.CEIL_CLIMB
