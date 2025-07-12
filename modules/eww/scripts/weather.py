#!/usr/bin/env python3

import urllib.parse
import urllib.request
import json
import os.path
from pathlib import Path
from argparse import ArgumentParser, BooleanOptionalAction


def get_display_from_wmo_code(wmo_code):
    wmo_lookup = {
        0: {"icon": "weather-clear", "description": "Clear"},
        1: {"icon": "weather-few-clouds", "description": "Mostly clear"},
        2: {"icon": "weather-few-clouds", "description": "Partly cloudy"},
        3: {"icon": "weather-overcast", "description": "Overcast"},
        45: {"icon": "weather-fog", "description": "Fog"},
        48: {"icon": "weather-fog", "description": "Rime fog"},
        51: {"icon": "weather-showers-scattered", "description": "Light drizzle"},
        53: {"icon": "weather-showers-scattered", "description": "Moderate drizzle"},
        55: {"icon": "weather-showers-scattered", "description": "Heavy drizzle"},
        56: {"icon": "weather-showers", "description": "Light freezing drizzle"},
        57: {"icon": "weather-showers", "description": "Heavy freezing drizzle"},
        61: {"icon": "weather-showers", "description": "Slight rain"},
        63: {"icon": "weather-showers", "description": "Moderate rain"},
        65: {"icon": "weather-showers", "description": "Heavy rain"},
        66: {"icon": "weather-showers", "description": "Light freezing rain"},
        67: {"icon": "weather-showers", "description": "Heavy freezing rain"},
        71: {"icon": "weather-snow", "description": "Light snow"},
        73: {"icon": "weather-snow", "description": "Moderate snow"},
        75: {"icon": "weather-snow", "description": "Heavy snow"},
        77: {"icon": "weather-snow", "description": "Snow grains"},
        80: {"icon": "weather-showers", "description": "Slight rain showers"},
        81: {"icon": "weather-showers", "description": "Moderate rain showers"},
        82: {"icon": "weather-showers", "description": "Violent rain showers"},
        85: {"icon": "weather-snow", "description": "Slight snow showers"},
        86: {"icon": "weather-snow", "description": "Heavy snow showers"},
        95: {"icon": "weather-storm", "description": "Thunderstorm"},
        96: {"icon": "weather-storm", "description": "Thunderstorm with slight hail"},
        99: {"icon": "weather-storm", "description": "Thunderstorm with heavy hail"},
    }

    return wmo_lookup.get(
        wmo_code, {"icon": "weather-severe-alert", "description": "Unknown"}
    )


cache_path = os.path.join(Path.home(), ".cache", "eww", "weather")
Path(cache_path).mkdir(parents=True, exist_ok=True)


def get_cache_path(selected):
    return os.path.join(cache_path, selected)


def cache_value(value, selected):
    cache_file_path = get_cache_path(selected)

    with open(cache_file_path, "w") as file:
        file.write(str(value))


parser = ArgumentParser(description="Weather fetching for dashboard")
parser.add_argument("--select", choices=["icon", "description", "temperature"])

args = vars(parser.parse_args())

if args["select"] is not None:
    with open(get_cache_path(args["select"]), "r") as file:
        print(file.read())
    exit(0)

base_url = "https://api.open-meteo.com/v1/forecast"

params = urllib.parse.urlencode(
    {
        "latitude": -37.7693349,
        "longitude": 144.9990326,
        "current": "temperature_2m,weather_code,rain",
        "timezone": "Australia/Sydney",
        "forecast_days": 1,
    }
)

url = f"{base_url}/?{params}"
res = urllib.request.urlopen(url)
charset = res.headers.get_content_charset() or "utf-8"

result = json.loads(res.read().decode(charset))
current = result["current"]

display_values = get_display_from_wmo_code(current["weather_code"])

cache_value(current["temperature_2m"], "temperature")
cache_value(display_values["icon"], "icon")
cache_value(display_values["description"], "description")
