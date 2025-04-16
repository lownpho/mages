extends Node

# Declaration of global event signals, each node is then responsible for connecting to the signals it needs
# and emitting them when necessary

signal player_position_changed(position: Vector2)
