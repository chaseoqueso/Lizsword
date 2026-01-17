class_name Player
extends CharacterBody2D

@export_group("Movement")
@export var max_speed: float = 100
@export var accel: float = 500

@export_group("Aerial Movement")
@export var air_accel: float = 500
@export var gravity: float = 200
@export var jump_velocity: float = 100
@export var coyote_time: float = 0.2

@export_group("Climbing")
@export var climb_speed: float = 100
@export var wall_jump_velocity: float = 100
@export var wall_jump_angle: float = 45
@export var ceil_jump_velocity: float = 100
@export var climb_jump_coyote_time: float = 0.2

@export_group("Charge Attack")
@export var charge_time: float = 1
@export var min_launch_velocity: float = 200
@export var max_launch_velocity: float = 500
@export var final_bounce_velocity: float = 200
@export var air_charge_slowdown_factor: float = 0.5

@export_group("Grappling")
@export var outer_grapple_range: float = 320
@export var target_grapple_range: float = 160
@export var grapple_reel_in_velocity: float = 320
@export var grapple_reel_out_velocity: float = 80
@export var grapple_reel_accel: float = 640

enum PlayerState { IDLE, RUNNING, CHARGING, LAUNCHING, WALL_CLIMB, CEIL_CLIMB, GRAPPLING }

var current_state: PlayerState
var remaining_bounces: int
var current_charge: float
var current_coyote_time: float
var current_wall_coyote_time: float
var wall_normal: Vector2
var air_charge_speed: float
var was_on_floor: bool
var grapple_point: Area2D
var grapple_angular_speed: float
var prev_grapple_radius: float
var prev_grapple_velocity: Vector2
var grapple_reel_speed: float


func _ready() -> void:
	current_state = PlayerState.IDLE
	remaining_bounces = 0
	current_charge = 0
	air_charge_speed = -1
	current_coyote_time = 0
	current_wall_coyote_time = 0
	was_on_floor = false
	grapple_point = null
	grapple_angular_speed = 0
	grapple_reel_speed = 0
	Globals.player_ref = self

func _process(delta: float) -> void:
	var inputX := Input.get_action_strength("right") - Input.get_action_strength("left")

	# Tick down coyote time
	if(current_coyote_time > 0):
		current_coyote_time -= delta
	if(current_wall_coyote_time > 0):
		current_wall_coyote_time -= delta

	# Animation Selection
	$AnimatedSprite2D.rotation = 0
	var reset_flip_v := true
	var should_flip_h := false

	if current_state != PlayerState.GRAPPLING \
	   and Input.is_action_pressed("grapple") \
	   and try_grapple(get_global_mouse_position(), delta):
		change_state(PlayerState.GRAPPLING)
	if current_state == PlayerState.CHARGING:
		if current_charge < 1:
			$AnimatedSprite2D.play("charge")
		else:
			$AnimatedSprite2D.play("chargeMax")
		reset_flip_v = false
		$AnimatedSprite2D.flip_h = get_local_mouse_position().x < 0
	elif current_state == PlayerState.LAUNCHING:
		$AnimatedSprite2D.play("launch")
	elif current_state == PlayerState.WALL_CLIMB:
		$AnimatedSprite2D.play("climb")
		$AnimatedSprite2D.flip_h = wall_normal.x < 0
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

	var apply_friction := func(affect_y := false):
		velocity.x -= sign(velocity.x) * current_accel * delta
		if abs(velocity.x) <= current_accel * delta:
			velocity.x = 0

		if affect_y:
			velocity.y -= sign(velocity.y) * current_accel * delta
			if abs(velocity.y) <= current_accel * delta:
				velocity.y = 0

	var apply_gravity := func(g = gravity):
		velocity.y += g * delta

	if current_state == PlayerState.CHARGING:
		# Charge up
		current_charge += delta / charge_time
		if current_charge > 1:
			current_charge = 1
		
		if is_on_floor() or is_on_wall() or is_on_ceiling():
			apply_friction.call()
		else:
			# Apply a slow-mo effect to the player's movement by decreasing
			# air resistance and gravity

			if !is_mostly_on_wall() and !is_mostly_on_ceiling():
				apply_gravity.call(gravity / 2)

			# Instead of the velocity decreasing all the way to 0, 
			# if we have a target value, approach that target
			if air_charge_speed > 0 and velocity.length() > air_charge_speed:
				apply_friction.call(true)
			else:
				air_charge_speed = -1

	elif current_state == PlayerState.GRAPPLING and grapple_point != null:
		var grapple_pos := grapple_point.global_position
		var from_grapple_to_player := global_position - grapple_pos
		var radius := from_grapple_to_player.length()

		# Override velocity magnitude to be affected only by gravity while grappling
		velocity = velocity.normalized() * prev_grapple_velocity.length()

		# Apply input and gravity
		apply_gravity.call()

		print(velocity)
		
		var ortho := (-from_grapple_to_player).orthogonal()
		var tangential_velocity: float = velocity.project(ortho).length() * sign(velocity.dot(ortho))

		# Move radius toward the target
		if !is_equal_approx(radius, target_grapple_range):
			if radius < target_grapple_range:
				grapple_reel_speed = min(grapple_reel_speed + grapple_reel_accel * delta, grapple_reel_out_velocity)
				radius = min(radius + grapple_reel_speed*delta, target_grapple_range)
			else:
				grapple_reel_speed = max(grapple_reel_speed - grapple_reel_accel * delta, -grapple_reel_in_velocity)
				radius = max(radius + grapple_reel_speed*delta, target_grapple_range)

		# If we hit target radius, cancel grapple reeling
		if is_equal_approx(radius, target_grapple_range):	
			grapple_reel_speed = 0

		# w = v / r
		grapple_angular_speed = tangential_velocity / radius

		# Apply a velocity that moves toward target point
		var new_angle := from_grapple_to_player.angle() + grapple_angular_speed * delta
		var new_pos := grapple_pos + Vector2.from_angle(new_angle) * radius
		velocity = (new_pos - global_position).normalized() * velocity.length()

		# Update changes to velocity
		prev_grapple_velocity = velocity

	elif is_climbing():
		# Always allow movement in all directions while climbing,
		# worst case the player just falls off the wall
		velocity.x = inputX * climb_speed
		velocity.y = -inputY * climb_speed

		# Apply a small velocity in the direction of the wall/ceiling
		# to keep sticking to it, if not pressing perpendicular movement
		if inputX != 0 or inputY != 0:
			if inputX == 0 and current_state == PlayerState.WALL_CLIMB:
				velocity.x = -wall_normal.x
			elif inputY == 0 and current_state == PlayerState.CEIL_CLIMB:
				velocity.y = -1
			# print(velocity)
			
	elif current_state != PlayerState.LAUNCHING:
		# Apply gravity
		apply_gravity.call()

		if is_on_floor():
			current_coyote_time = coyote_time

		# Handle movement input
		if is_on_floor() and inputX == 0:
			apply_friction.call()
		else:
			velocity.x += inputX * current_accel * delta
			if abs(velocity.x) > max_speed:
				velocity.x = sign(velocity.x) * max_speed

	# print(velocity)

	##########################################
	### Apply Velocity & Handle Collisions ###
	##########################################

	# Move the player
	if current_state != PlayerState.LAUNCHING:
		rotation = 0
		# print(str(current_state) + " " + str(velocity))
		move_and_slide()
		if is_climbing() and not(is_mostly_on_wall() or is_mostly_on_ceiling()):
			change_state(PlayerState.IDLE)
			wall_normal = Vector2.ZERO
		elif current_state != PlayerState.CHARGING:
			if is_mostly_on_wall(): # and (inputX == -get_wall_normal().x or current_state == PlayerState.CEIL_CLIMB):
				change_state(PlayerState.WALL_CLIMB)
			elif is_mostly_on_ceiling() and (inputY == 1 or current_state == PlayerState.WALL_CLIMB):
				change_state(PlayerState.CEIL_CLIMB)
				wall_normal = Vector2.ZERO
	else: # Launching
		var collision := move_and_collide(velocity * delta)
		while collision:
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

			if data == null:
				break
			else:
				if data.get_collision_polygons_count(1) > 0:
					velocity = velocity.bounce(collision.get_normal())
					rotation = Vector2.UP.angle_to(velocity)
					remaining_bounces -= 1

					if remaining_bounces <= 0:
						change_state(PlayerState.IDLE)
						var up_boost := Vector2.UP * (collision.get_normal().dot(Vector2.UP) + 1) * 0.25
						velocity = (velocity.normalized() + up_boost) * final_bounce_velocity
						break
						
					collision = move_and_collide(velocity * delta)
				else:
					if abs(collision.get_normal().dot(Vector2.UP)) < 0.5:
						change_state(PlayerState.WALL_CLIMB)
					else:
						change_state(PlayerState.CEIL_CLIMB)
					
					rotation = 0
					velocity = -collision.get_normal() * 10
					move_and_collide(velocity)
					wall_normal = collision.get_normal()
					break

func _input(event):
	if event.is_action_pressed("attack"):
		# Globals.is_attacking = true
		change_state(PlayerState.CHARGING)
	elif event.is_action_released("attack") and current_state == PlayerState.CHARGING:     # If we are in the charge state but attack is not pressed, launch
		velocity = get_local_mouse_position().normalized() * lerpf(min_launch_velocity, max_launch_velocity, current_charge)
		current_charge = 0
		remaining_bounces = 3
		change_state(PlayerState.LAUNCHING)

	if event.is_action_pressed("jump") and ((is_on_floor() or current_coyote_time > 0) or (is_climbing() or current_wall_coyote_time > 0)):
		if current_state == PlayerState.WALL_CLIMB or current_wall_coyote_time > 0:
			velocity = Vector2.from_angle(deg_to_rad(-wall_jump_angle)) * wall_jump_velocity
			velocity.x *= get_wall_normal().x 
		elif is_on_floor() or current_coyote_time > 0:
			velocity.y = -jump_velocity
		elif current_state == PlayerState.CEIL_CLIMB:
			velocity.y = ceil_jump_velocity

		$AnimatedSprite2D.play("jump")
		change_state(PlayerState.IDLE)

	# Code for checking grapple input is in _process because it checks while key is held
	if event.is_action_released("grapple"):
		ungrapple()


func change_state(new_state: PlayerState):
	if current_state == new_state:
		return
	
	# If fell off of wall, allow coyote time to wall jump
	if is_climbing() and new_state == PlayerState.IDLE:
		current_wall_coyote_time = climb_jump_coyote_time
	

	# Deal with exiting state
	if current_state == PlayerState.LAUNCHING:
		enable_launch_collider(false)
	elif current_state == PlayerState.GRAPPLING:
		grapple_angular_speed = 0

	# Deal with entering state
	if new_state == PlayerState.WALL_CLIMB:
		wall_normal = get_wall_normal()
	elif new_state == PlayerState.CHARGING:
		# Set slow-mo velocity if midair charging
		if not is_on_floor():
			air_charge_speed = velocity.length() * air_charge_slowdown_factor
	elif new_state == PlayerState.LAUNCHING:
		rotation = Vector2.UP.angle_to(velocity)
		enable_launch_collider()
	elif new_state == PlayerState.GRAPPLING:
		# if we just started grappling, set angular velocity based on current velocity
		var from_player_to_grapple := grapple_point.global_position - global_position
		var ortho := from_player_to_grapple.orthogonal()
		var tangential_velocity: float = velocity.project(ortho).length() * sign(velocity.dot(ortho))
		grapple_angular_speed = tangential_velocity / from_player_to_grapple.length()
		prev_grapple_radius = from_player_to_grapple.length()
		prev_grapple_velocity = velocity
		grapple_reel_speed = 0

	current_state = new_state

func enable_launch_collider(enabled := true):
	$CollisionPolygon2D.disabled = !enabled
	$CollisionShape2D.disabled = enabled

func try_grapple(mouse_position: Vector2, delta: float):
	# create a circle with diameter equal to distance traveled
	var circle := CircleShape2D.new()
	var last_frame_motion := velocity * delta
	circle.radius = last_frame_motion.length()/2

	# create a transform with the position to cast from
	var t := Transform2D(0, position - last_frame_motion/2)

	# create a query with the required properties
	var query := PhysicsShapeQueryParameters2D.new()
	query.collide_with_areas = true
	query.collision_mask = 1 << 2
	query.motion = (mouse_position - position).normalized() * (outer_grapple_range - last_frame_motion.length()/2)
	query.shape = circle
	query.transform = t

	# perform the raycast
	var space_state := get_world_2d().direct_space_state
	var hits := space_state.intersect_shape(query)
	if hits:
		grapple_point = hits[0].collider
		change_state(PlayerState.GRAPPLING)
	

func ungrapple():
	if current_state == PlayerState.GRAPPLING:
		change_state(PlayerState.IDLE)

func is_climbing():
	return current_state == PlayerState.WALL_CLIMB or current_state == PlayerState.CEIL_CLIMB

func is_mostly_on_wall():
	if !is_on_wall():
		return false

	var space_state := get_world_2d().direct_space_state
	# use global coordinates, not local to node
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position - get_wall_normal() * (($CollisionShape2D.shape as RectangleShape2D).size.x/1 + 1))
	var result := space_state.intersect_ray(query)
	# if result:
	# 	print(result)
	return result.size() > 0

func is_mostly_on_ceiling():
	if !is_on_ceiling():
		return false

	var space_state := get_world_2d().direct_space_state
	# use global coordinates, not local to node
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(0, -($CollisionShape2D.shape as RectangleShape2D).size.y/1 + 1))
	var result := space_state.intersect_ray(query)
	# if result:
	# 	print(result)
	return result.size() > 0

# func _on_animated_sprite_2d_animation_finished() -> void:
#     Globals.is_attacking = false
