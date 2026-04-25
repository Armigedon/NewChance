extends Node

enum Location { MAIN_HALL, UPSTAIRS }

signal location_changed(new_location: Location)

var current_location: Location = Location.MAIN_HALL

func transition_to(location: Location) -> void:
    if location == current_location:
        return
    current_location = location
    location_changed.emit(location)
