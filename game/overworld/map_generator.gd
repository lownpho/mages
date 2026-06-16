class_name MapGenerator extends RefCounted
## Base contract for everything that builds a map — the overworld and every dungeon.
## A generator is pure logic: it reads a GenContext and paints/spawns into it, then is
## thrown away. Subclasses override generate().

func generate(_ctx: GenContext) -> void:
	push_error("MapGenerator.generate() is abstract — override it")
