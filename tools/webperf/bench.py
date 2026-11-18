"""网页播放器本机测量台。
  python bench.py fetch <仓库根> <对局号>     从正式播放器站点把这一局的 end.json + 全部块拉到 <仓库根>/.out/webperf/streams/<id>/(只读 GET)
  python bench.py serve <仓库根> [端口]        起本机静态站: /player/<版本>/ = build/webplayer/, /player/streams/ = 上面拉下来的, 其余 404
"""
import http.server
import json
import os
import sys
import urllib.request

ORIGIN = "https://arena.turtlearena.xyz"


def fetch(root, mid):
    d = os.path.join(root, ".out", "webperf", "streams", mid)
    os.makedirs(d, exist_ok=True)
    op = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    op.addheaders = [("User-Agent", "turtle-bench/1.0")]

    def get(name):
        with op.open("%s/player/streams/%s/%s" % (ORIGIN, mid, name), timeout=60) as r:
            b = r.read()
        open(os.path.join(d, name), "wb").write(b)
        return b
    end = json.loads(get("end.json"))
    n = int(end.get("chunks") or 0)
    for i in range(n):
        get("%06d.bin" % i)
    print("end.json version=%s chunks=%d last_step=%s -> %s" % (end.get("client_version"), n, end.get("last_step"), d))


def serve(root, port):
    build = os.path.join(root, "build", "webplayer")
    streams = os.path.join(root, ".out", "webperf", "streams")
    ver = json.load(open(os.path.join(build, "webplayer.json"), encoding="utf-8")).get("version") \
        if os.path.exists(os.path.join(build, "webplayer.json")) else None

    class H(http.server.SimpleHTTPRequestHandler):
        def translate_path(self, path):
            p = path.split("?", 1)[0]
            if p.startswith("/player/streams/"):
                return os.path.join(streams, *p[len("/player/streams/"):].split("/"))
            if ver and p.startswith("/player/%s/" % ver):
                rest = p[len("/player/%s/" % ver):] or "index.html"
                return os.path.join(build, *rest.split("/"))
            return os.path.join(root, ".out", "webperf", "_nothing_")

        def end_headers(self):
            self.send_header("Cache-Control", "no-cache")
            super().end_headers()

        def log_message(self, fmt, *a):
            sys.stderr.write("%s\n" % (fmt % a))
    H.extensions_map[".wasm"] = "application/wasm"
    print("serving http://127.0.0.1:%d/player/%s/  (version %s)" % (port, ver, ver), flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()


if __name__ == "__main__":
    if sys.argv[1] == "fetch":
        fetch(sys.argv[2], sys.argv[3])
    else:
        serve(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 8765)
