extends VBoxContainer
## Catalogue surface also acts as the inventory return target for installed parts.

var game: Node

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("installed_part") is String

func _drop_data(_position: Vector2, data: Variant) -> void:
	if is_instance_valid(game) and data is Dictionary and data.get("installed_part") is String:
		game._remove_part_to_catalogue(str(data.installed_part))
