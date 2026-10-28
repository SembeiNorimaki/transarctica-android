extends Node

const FOOTPRINTS = {
}

const TYPES = {
    "LocomotiveWagon": {
        "horizontal_scene": preload("res://scenes/wagons/locomotive_wagon.tscn"),
        "team": "Player",
        "horizontal_size": Vector2i(256, 66),
        "stores": [],
        "default_cargo": "",
        "capacity": 0,
        "footprint": "wagon_large"
    },
    "BarracksWagon": {
        "horizontal_scene": preload("res://scenes/wagons/barracks_wagon.tscn"),
        "navigation_atlas_file": "res://assets/sprites/wagons/navigation/nav_BarracksWagon.png",
        "navigation_atlas_orientations": ["SE", "S", "SW", "W", "NW", "N", "NE", "E"],
        "navigation_atlas_cargo": ["Empty_Soldiers"],
        "team": "Player",
        "horizontal_size": Vector2i(128, 48),
        "navigation_size": Vector2i(78, 55),
        "stores": ["Soldiers"],
        "default_cargo": "Soldiers",
        "capacity": 5,
        "footprint": "wagon_small"
    },
    "CannonWagon": {
        "horizontal_scene": preload("res://scenes/wagons/cannon_wagon.tscn"),
        "navigation_atlas_file": "res://assets/sprites/wagons/navigation/nav_CannonWagon.png",
        "navigation_atlas_orientations": ["SE", "S", "SW", "W", "NW", "N", "NE", "E"],
        "navigation_atlas_cargo": ["Empty_Ammunition"],
        "team": "Player",
        "horizontal_size": Vector2i(128, 58),
        "navigation_size": Vector2i(78, 55),
        "stores": ["Ammunition"],
        "default_cargo": "Ammunition",
        "capacity": 20,
        "footprint": "wagon_small"
    },
    "MerchandiseWagon": {
        "horizontal_scene": preload("res://scenes/wagons/merchandise_wagon.tscn"),
        "navigation_atlas_file": "res://assets/sprites/wagons/navigation/nav_MerchandiseWagon.png",
        "navigation_atlas_orientations": ["SE", "S", "SW", "W", "NW", "N", "NE", "E"],
        "navigation_atlas_cargo": ["Empty_Crate"],
        "team": "Player",
        "horizontal_size": Vector2i(128, 46),
        "navigation_size": Vector2i(78, 55),
        "stores": ["Crate"],
        "default_cargo": "Crate",
        "capacity": 10,
        "footprint": "wagon_small"
    },
    "TenderWagon": {
        "horizontal_scene": preload("res://scenes/wagons/tender_wagon.tscn"),
        "navigation_atlas_file": "res://assets/sprites/wagons/navigation/nav_TenderWagon.png",
        "navigation_atlas_orientations": ["SE", "S", "SW", "W", "NW", "N", "NE", "E"],
        "navigation_atlas_cargo": ["Empty_Coal"],
        "team": "Player",
        "horizontal_size": Vector2i(128, 45),
        "navigation_size": Vector2i(78, 55),
        "stores": ["Coal"],
        "default_cargo": "Coal",
        "capacity": 100,
        "footprint": "wagon_small"
    },


}
