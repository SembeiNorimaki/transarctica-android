class_name PriceModel
extends RefCounted
# The formulas of the economy, in one place and with no state, so they are easy to test and tune.
#
# The price of a resource in a city is NOT stored: it is always computed from
#     base price (nominal price x the city's factor)
#   x stock multiplier   (how much the city has, compared with how much it wants: PriceModel.stock_multiplier)
#   x global index       (the world economy: GlobalEconomyManager)
# so it can never get out of sync with the stock, and a saved game needs no prices.

## How strongly the price follows the stock. 0.5: a stock four times smaller than wanted doubles the price.
const ELASTICITY := 0.5
const MIN_STOCK_MULTIPLIER := 0.5 # a city drowning in a resource pays half
const MAX_STOCK_MULTIPLIER := 2.5 # a city with none of it pays two and a half times
const MIN_RATIO := 0.05 # stock/target below this counts as this (avoids dividing by zero)

# The global index (one per resource) moves between these
const MIN_GLOBAL_INDEX := 0.6
const MAX_GLOBAL_INDEX := 1.8
## How strongly the index follows the scarcity of the resource in the whole world.
const GLOBAL_ELASTICITY := 0.3
# Shocks (events) may push the final index further, but not past these
const MIN_EFFECTIVE_INDEX := 0.25
const MAX_EFFECTIVE_INDEX := 4.0


## 1 when the city has what it wants. Above 1 when it has less (it NEEDS the resource: demand),
## below 1 when it has more (it is supplied). A city that wants nothing (target 0) has no effect.
static func stock_multiplier(stock: int, target: int) -> float:
    if target <= 0:
        return 1.0
    var ratio := maxf(float(stock) / float(target), MIN_RATIO)
    return clampf(pow(ratio, -ELASTICITY), MIN_STOCK_MULTIPLIER, MAX_STOCK_MULTIPLIER)


## The index that the whole world's stock calls for: more than 1 when all the cities together
## have less than they want.
static func scarcity_index(total_stock: int, total_target: int) -> float:
    if total_target <= 0:
        return 1.0
    var ratio := maxf(float(total_stock) / float(total_target), MIN_RATIO)
    return clampf(pow(ratio, -GLOBAL_ELASTICITY), MIN_GLOBAL_INDEX, MAX_GLOBAL_INDEX)


## A price in whole coins. 0 stays 0 (a side the place doesn't trade); otherwise at least 1. Both
## sides of a resource use the same multiplier and this rounding never changes their order, so
## buy >= sell holds whenever it holds for the base prices (no infinite money).
static func price(base: float, multiplier: float) -> int:
    if base <= 0.0:
        return 0
    return maxi(roundi(base * multiplier), 1)
