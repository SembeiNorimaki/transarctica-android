class_name GameCalendar
extends RefCounted
# The calendar of the game: the time is a number of minutes since 1 Jan 2100, 00:00 (it is what
# GameState saves). Real calendar rules (a leap year every 4 years, except centuries not divisible
# by 400: 2100 has 365 days, 2104 has 366).

const START_YEAR := 2100
const MINUTES_PER_DAY := 1440
const MONTH_NAMES: Array[String] = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
const DAYS_IN_MONTH: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]


static func is_leap_year(year: int) -> bool:
    return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0

static func days_in_month(year: int, month: int) -> int: # month 1 to 12
    return 29 if month == 2 and is_leap_year(year) else DAYS_IN_MONTH[month - 1]

static func days_in_year(year: int) -> int:
    return 366 if is_leap_year(year) else 365


## Days since 1 Jan 2100 (day 0) that the time is in.
static func day_of(minutes: int) -> int:
    return maxi(minutes, 0) / MINUTES_PER_DAY

static func hour_of(minutes: int) -> int:
    return (maxi(minutes, 0) % MINUTES_PER_DAY) / 60

static func minute_of(minutes: int) -> int:
    return maxi(minutes, 0) % 60


## {"year": 2100, "month": 1 to 12, "day": 1 to 31} of a day number (0 = 1 Jan 2100)
static func date_of(day_number: int) -> Dictionary:
    var days_left := maxi(day_number, 0)
    var year := START_YEAR
    while days_left >= days_in_year(year):
        days_left -= days_in_year(year)
        year += 1
    var month := 1
    while days_left >= days_in_month(year, month):
        days_left -= days_in_month(year, month)
        month += 1
    return {"year": year, "month": month, "day": days_left + 1}


## "1 jan 2100, 08h30". Lower case and no colon, because it is drawn with the game's bitmap font
## (it has a to z, digits, space and , . ! ? only).
static func format(minutes: int) -> String:
    var date := date_of(day_of(minutes))
    return "%d %s %d, %02dh%02d" % [date["day"], MONTH_NAMES[date["month"] - 1], date["year"], hour_of(minutes), minute_of(minutes)]
