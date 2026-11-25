#!/usr/bin/env bash
## run_some_tests.sh —— 并行单跑几条自证测试(隔离存档、不连服务器), 每条一行结论(2026-11-25 匕首批修预检用)
##   JOBS=4 bash tools/oneoff/run_some_tests.sh verify_a verify_b ...
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe}"
mkdir -p .out/some
one() {
	t="$1"; U=$(mktemp -d)
	fr=$(source <(sed -n '/^frames_for ()/,/^}/p' run-tests.sh); frames_for "$t")
	[ -z "$fr" ] && fr=60000
	APPDATA=$U XDG_DATA_HOME=$U TURTLE_SUPABASE=" " timeout 1200 "$GODOT" --headless --audio-driver Dummy --path . "res://tests/$t.tscn" --quit-after "$fr" > ".out/some/$t.log" 2>&1
	if grep -q "ALL PASS" ".out/some/$t.log" && ! grep -qE "SCRIPT ERROR|Parse Error" ".out/some/$t.log"; then
		echo "✓ $t"
	else
		echo "✗ $t"; grep -E "\[FAIL\]|SCRIPT ERROR|Parse Error" ".out/some/$t.log" | head -3 | cut -c1-260 | sed 's/^/      /'
	fi
}
export -f one; export GODOT
printf '%s\n' "$@" | xargs -P "${JOBS:-4}" -I{} bash -c 'one {}'
