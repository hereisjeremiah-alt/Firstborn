class_name TimeSystem
extends RefCounted
## Two clocks.
##  - `t` is simulation time in "work days": hunger, thirst, sleep, production and building all
##    run on it, so people and animals live at the same pace as always.
##  - The calendar runs CAL_SCALE (5x) faster: dates, months, years, seasons, the visible
##    day/night cycle and aging follow it. A Monolith can also push the calendar forward.
## Real-world calendar: 365-day years, 12 months, seasons of three months.
## Spring = Mar–May, Summer = Jun–Aug, Fall = Sep–Nov, Winter = Dec–Feb. A new game starts on March 1.

const CAL_SCALE := 5.0

var t := 0.30          # elapsed simulation days since the start (fractional)
var skip_days := 0.0   # calendar days skipped with a Monolith


func advance(real_dt: float) -> void:
	t += real_dt / Defs.DAY_SECONDS


## Simulation day counter (for once-a-day upkeep).
func day() -> int:
	return floori(t)


## Body clock: the hour people and animals live by (sleep, night predators, fires).
func tod() -> float:
	return t - floorf(t)


func hour() -> float:
	return tod() * 24.0


## Calendar days elapsed (5x faster than simulation days, plus Monolith skips).
func cal() -> float:
	return t * CAL_SCALE + skip_days


func cal_day() -> int:
	return floori(cal())


## Calendar years elapsed since the start (fractional).
func cal_years() -> float:
	return cal() / float(Defs.YEAR_DAYS)


## Hour of the visible day (drives the day/night lighting and the clock).
func cal_hour() -> float:
	var c := cal()
	return (c - floorf(c)) * 24.0


func cal_is_night() -> bool:
	var hr := cal_hour()
	return hr >= 21.0 or hr < 5.5


## 0..364, 0 = January 1.
func day_of_year() -> int:
	return (cal_day() + Defs.START_DOY) % Defs.YEAR_DAYS


func year() -> int:
	return (cal_day() + Defs.START_DOY) / Defs.YEAR_DAYS + 1


func month() -> int:
	var d := day_of_year()
	for m in 12:
		var len: int = Defs.MONTH_DAYS[m]
		if d < len:
			return m
		d -= len
	return 11


func day_of_month() -> int:
	var d := day_of_year()
	for m in 12:
		var len: int = Defs.MONTH_DAYS[m]
		if d < len:
			return d + 1
		d -= len
	return 31


func season() -> int:
	var m := month()
	if m >= 2 and m <= 4:
		return 0
	if m >= 5 and m <= 7:
		return 1
	if m >= 8 and m <= 10:
		return 2
	return 3


func season_name() -> String:
	return Defs.SEASONS[season()]


func month_name() -> String:
	return Defs.MONTHS[month()]


func date_text() -> String:
	return "%s %d, Year %d" % [month_name(), day_of_month(), year()]


## Days until the next December 1 (start of winter).
func days_to_winter() -> int:
	var dec1 := 334
	var d := day_of_year()
	return (dec1 - d + Defs.YEAR_DAYS) % Defs.YEAR_DAYS


## Smooth yearly temperature offset: warmest mid-July (+7 °C), coldest mid-January (-14 °C).
func season_temp() -> float:
	var doy := fmod(cal() + Defs.START_DOY, float(Defs.YEAR_DAYS))
	return -3.5 + 10.5 * cos(TAU * (doy - 196.0) / Defs.YEAR_DAYS)


func is_night() -> bool:
	var hr := hour()
	return hr >= 21.0 or hr < 5.5


func phase_name() -> String:
	var hr := cal_hour()
	if hr < 5.5:
		return "Night"
	if hr < 9.0:
		return "Morning"
	if hr < 17.5:
		return "Day"
	if hr < 21.0:
		return "Evening"
	return "Night"


func clock_text() -> String:
	var hr := cal_hour()
	return "%02d:%02d" % [int(hr), int((hr - floorf(hr)) * 60.0)]


## Ambient light colour for the CanvasModulate.
func light_color() -> Color:
	var hr := cal_hour()
	var night := Color(0.22, 0.26, 0.45)
	var dawn := Color(0.95, 0.72, 0.58)
	var day_c := Color(1.0, 1.0, 1.0)
	var dusk := Color(0.92, 0.60, 0.52)
	if hr < 4.5:
		return night
	if hr < 6.0:
		return night.lerp(dawn, (hr - 4.5) / 1.5)
	if hr < 8.0:
		return dawn.lerp(day_c, (hr - 6.0) / 2.0)
	if hr < 17.5:
		return day_c
	if hr < 19.5:
		return day_c.lerp(dusk, (hr - 17.5) / 2.0)
	if hr < 21.5:
		return dusk.lerp(night, (hr - 19.5) / 2.0)
	return night


## 0 at full daylight, 1 at full night (used for light intensity).
func darkness() -> float:
	var c := light_color()
	return clampf(1.0 - (c.r + c.g + c.b) / 3.0, 0.0, 1.0) * 1.6
