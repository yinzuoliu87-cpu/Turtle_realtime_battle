#!/usr/bin/env bash
## rec_mask.sh —— 面具批录像台逐条录(2026-11-25 自查用; 右屏、静音、单独存档目录)
##   bash tools/oneoff/rec_dagger.sh ninja_show:2 fold knife ...   (冒号后 = REC_ZOOM)
cd "$(dirname "$0")/../.."
OUT="${OUT:-.out/mask_rec}"
FF="${FF:-D:/oopz/ffmpeg.exe}"
mkdir -p "$OUT"
for spec in "$@"; do
	c="${spec%%:*}"; z=""
	[ "$spec" != "$c" ] && z="${spec#*:}"
	U=$(mktemp -d)
	ZOOM=()
	[ -n "$z" ] && ZOOM=("REC_ZOOM=$z")
	env APPDATA="$U" XDG_DATA_HOME="$U" SHIP=1 TURTLE_SUPABASE=" " TURTLE_BACKEND=" " REC_CASE="$c" "${ZOOM[@]}" WINDOW=1 \
		bash godot-quiet.sh --path . --resolution 1280x720 --position 2000,80 --write-movie "$OUT/$c.avi" --fixed-fps 30 \
		res://tests/_rec_eq_stage.tscn > "$OUT/$c.log" 2>&1
	"$FF" -y -loglevel error -i "$OUT/$c.avi" -c:v libx264 -pix_fmt yuv420p -crf 20 "$OUT/$c.mp4" && rm -f "$OUT/$c.avi"
	echo "$c 完成: $(grep -c '\[EV\]' "$OUT/$c.log") 个事件, 报错 $(grep -c 'SCRIPT ERROR' "$OUT/$c.log")"
done
