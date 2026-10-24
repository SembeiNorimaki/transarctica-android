class_name GameConstants

enum Orientation {
    N,
    E,
    S,
    W
}

enum Gear {
    NEUTRAL, # no power: the train brakes
    DRIVE, # forward
    REVERSE # backwards (only the horizontal trains use it)
}