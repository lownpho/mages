extends Node
class_name FSM

signal state_changed(previous_state, new_state)

@export var initial_state: String = ""
@export var auto_start: bool = true
@export var state_names: Array[String] = []

var current_state: State
var states: Dictionary = {}

func _ready() -> void:
	# Initialize states
	for state_name in state_names:
		var state = State.new()
		state.name = state_name
		add_child(state)
	
	# Initialize states dictionary (not sure if necessary)
	for child in get_children():
		if child is State:
			states[child.name] = child

	# Set initial state if specified, otherwise use first state
	if auto_start:
		if initial_state != "" and states.has(initial_state):
			transition_to(initial_state)
		elif states.size() > 0:
			current_state = states.values()[0]
			current_state.emit_enter()


func _process(delta: float) -> void:
	if current_state:
		current_state.emit_update(delta)

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.emit_physics_update(delta)

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.emit_input(event)

func transition_to(state_name: String) -> void:
	if not state_name in states:
		print("State not found: ", state_name)
		return
		
	if current_state:
		current_state.emit_exit()
		
	var previous_state = current_state
	current_state = states[state_name]
	current_state.emit_enter()
	
	emit_signal("state_changed", previous_state, current_state)
