while [[ "$#" > 0 ]]; do
  case "$1" in
    -r|--return) RETURN=1; shift;;
    -d|--date) DATE="$2"; shift 2;;
    -t|--time) TIME="$2"; shift 2;;
    *) echo "Unknown parameter $1"; exit 1;;
  esac
done

if [ ! -z "$RETURN" ]; then
  sudo systemsetup -setusingnetworktime on 2>/dev/null 1>&2
  echo "🌏 Returned to the present day!"
  exit 0
fi

if [ -z "$DATE" ]; then cat << EOF
usage: delorian [--return] [--date <d>] [--time <t>]
Sets system time to the date <d> at time <t>
Expects date to be in format DD/MM/YY, time to be of HH:MM in 24-hour format.

Example:
delorian --return

delorian --date 02/09/24 --time 12:00

Time will default to 12:00 noon:
delorian -d 02/09/24
EOF
  exit 1
fi

DAY="$(echo $DATE | cut -d / -f 1)"
MONTH="$(echo $DATE | cut -d / -f 2)"
YEAR="$(echo $DATE | cut -d / -f 3)"

HOUR="$(echo $TIME | cut -d : -f 1)"
MINUTE="$(echo $TIME | cut -d : -f 2)"

[[ -z "$HOUR" ]] && HOUR="12"
[[ -z "$MINUTE" ]] && MINUTE="00"

sudo systemsetup -setusingnetworktime off 2>/dev/null 1>&2

if [ "$(sudo date "$MONTH$DAY$HOUR$MINUTE$YEAR" 2>/dev/null 1>&2)" == 0 ]; then
  echo "👽 Time travel successful!"
  exit 0
fi

echo "😭 Time travel failed! Resetting to network time."
sudo systemsetup -setusingnetworktime on 2>/dev/null 1>&2

