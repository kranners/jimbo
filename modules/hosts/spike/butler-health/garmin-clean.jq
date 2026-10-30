def kept_key:
  (test("(?i)name|title|description|note|comment|location|address|email|url|image|photo|owner|display|uuid|token|latitude|longitude|polyline|gps|geo|coordinate")
    or test("^(lat|lon|lng)|(Lat|Lon|Lng)([A-Z0-9]|$)"))
  | not;

def clean:
  if type == "object" then
    with_entries(select(.key | kept_key) | .value |= clean | select(.value != null and .value != [] and .value != {}))
  elif type == "array" then
    if length > 64 or (length > 0 and (.[0] | type) == "array") then null
    else map(clean | select(. != null))
    end
  elif type == "string" then
    if test("^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9:.]+)?Z?$") or test("^[A-Za-z][A-Za-z0-9_]{0,39}$") then . else null end
  else .
  end;

clean
