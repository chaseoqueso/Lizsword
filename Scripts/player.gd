extends CharacterBody2D

@export_group("Physics")
@export var max_speed: float = 100
@export var accel: float = 500
@export var gravity: float = 200
@export var jump_velocity: float = 100

@export_group("Charge Attack")
@export var charge_rate: float = 1
@export var max_charge: float = 2
@export var launch_velocity: float = 500

enum PlayerState { IDLE, RUNNING, CHARGING, LAUNCHING }

var current_state: PlayerState
var initial_gravity: float
var remaining_bounces: int
var current_charge: float

func _ready() -> void:
    initial_gravity = gravity
    current_state = PlayerState.IDLE
    remaining_bounces = 0
    current_charge = 0

func _process(delta: float) -> void:
    var inputX := Input.get_action_strength("right") - Input.get_action_strength("left")
    # if !Input.is_action_just_released("jump"):

    # Animation Selection
    if current_state == PlayerState.CHARGING:
        if current_charge < max_charge:
            $AnimatedSprite2D.play("charge")
        else:
            $AnimatedSprite2D.play("chargeMax")
    else:
        if is_on_floor():
            if inputX != 0:
                $AnimatedSprite2D.play("run")
                change_state(PlayerState.RUNNING)
            else:
                $AnimatedSprite2D.play("idle")
                change_state(PlayerState.IDLE)
        else:
            if velocity.y < 0:
                $AnimatedSprite2D.play("jump")
            else:
                $AnimatedSprite2D.play("fall")
    
        if inputX < 0:
            $AnimatedSprite2D.flip_h = true
        else:
            $AnimatedSprite2D.flip_h = false


func _physics_process(delta: float) -> void:
    if current_state == PlayerState.CHARGING:
        # Charge up
        current_charge += charge_rate * delta
        if current_charge > max_charge:
            current_charge = max_charge
    elif current_state != PlayerState.LAUNCHING:
        # Apply gravity
        velocity.y += gravity * delta

        # Handle movement input
        var inputX := Input.get_action_strength("right") - Input.get_action_strength("left")
        if inputX == 0:
            if abs(velocity.x) <= accel * delta:
                velocity.x = 0
            else:
                inputX = -sign(velocity.x)

        velocity.x += inputX * accel * delta
        if abs(velocity.x) > max_speed:
            velocity.x = sign(velocity.x) * max_speed
    
        # Handle climbing physics
        if PlayerGlobals.can_climb:
            if Input.is_action_pressed("up"):
                $AnimatedSprite2D.play("climb")	
                gravity = 0
                velocity.y = -160
            elif gravity == 0:
                velocity.y = 0
        else:
            gravity = initial_gravity

    # Move the player
    if current_state != PlayerState.LAUNCHING:
        move_and_slide()
    else:
        var collision := move_and_collide(velocity * delta)
        if collision:
            var collider: PhysicsBody2D = collision.get_collider()
            if collider.get_collision_layer_value(2):
                velocity = velocity.bounce(collision.get_normal())
                remaining_bounces -= 1

                if remaining_bounces <= 0:
                    change_state(PlayerState.IDLE)
            else:
                change_state(PlayerState.IDLE)


func _input(event):
    if event.is_action_pressed("attack"):
        # PlayerGlobals.is_attacking = true
        change_state(PlayerState.CHARGING)
    elif current_state == PlayerState.CHARGING:     # If we are in the charge state but attack is not pressed, launch
        print(get_local_mouse_position().normalized())
        velocity = get_local_mouse_position().normalized() * launch_velocity
        current_charge = 0
        remaining_bounces = 3
        change_state(PlayerState.LAUNCHING)

    if event.is_action_pressed("jump") and (is_on_floor() or (PlayerGlobals.can_climb and gravity == 0)):
        velocity.y = -jump_velocity
        gravity = initial_gravity
        $AnimatedSprite2D.play("jump")

func change_state(new_state: PlayerState):
    if current_state == new_state:
        return
    current_state = new_state

# func _on_animated_sprite_2d_animation_finished() -> void:
#     PlayerGlobals.is_attacking = false
