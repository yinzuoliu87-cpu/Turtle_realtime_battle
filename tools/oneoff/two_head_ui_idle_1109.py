"""变脸龟界面待机(2026-11-09): 四处界面立绘取图前先过 PetUiIdle.of。二进制读写、保留行尾、每处断言恰命中一次。"""
ROOT = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/"


def edit(rel, pairs):
    p = ROOT + rel
    b = open(p, "rb").read().decode("utf-8")
    crlf = "\r\n" in b
    s = b.replace("\r\n", "\n")
    for a, c in pairs:
        assert s.count(a) == 1, (rel, a[:80], s.count(a))
        s = s.replace(a, c)
    open(p, "wb").write((s.replace("\n", "\r\n") if crlf else s).encode("utf-8"))


NOTE = "\t## 界面待机帧补丁(变脸龟; PetUiIdle 头注释): 没登记逐帧待机图的龟换成界面那套, 不改 DataRegistry\n"

edit("scripts/util/unit_card_art.gd", [
    ("static func pet_body(pid: String) -> Array:\n\tvar pdef: Dictionary = DataRegistry.pet_by_id.get(pid, {})\n",
     "static func pet_body(pid: String) -> Array:\n" + NOTE + "\tvar pdef: Dictionary = PetUiIdle.of(DataRegistry.pet_by_id.get(pid, {}))\n"),
    ("\tvar tex: Texture2D = body[0]\n\tvar pdef: Dictionary = DataRegistry.pet_by_id.get(pid, {})\n",
     "\tvar tex: Texture2D = body[0]\n\tvar pdef: Dictionary = PetUiIdle.of(DataRegistry.pet_by_id.get(pid, {}))\n"),
])

edit("scripts/scenes/CodexScene.gd", [
    ("func _add_pet_portrait(cx: float, cy: float, pet: Dictionary, box: float) -> void:\n\tvar fid: String = str(pet.get(\"id\", \"\"))\n",
     "func _add_pet_portrait(cx: float, cy: float, pet_in: Dictionary, box: float) -> void:\n" + NOTE
     + "\tvar pet: Dictionary = PetUiIdle.of(pet_in)\n\tvar fid: String = str(pet.get(\"id\", \"\"))\n"),
])

edit("scripts/scenes/TeamSelectScene.gd", [
    ("func _apply_pet_idle_texture(tr: TextureRect, pet: Dictionary, autoplay: bool = true) -> void:\n\ttr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST\n",
     "func _apply_pet_idle_texture(tr: TextureRect, pet_in: Dictionary, autoplay: bool = true) -> void:\n" + NOTE
     + "\tvar pet: Dictionary = PetUiIdle.of(pet_in)\n\ttr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST\n"),
])

edit("scripts/scenes/bracket/champion_ui.gd", [
    ("\tvar pet: Dictionary = DataRegistry.pet_by_id.get(id, {})\n\tvar img := str(pet.get(\"img\", \"\"))\n\tvar path := \"res://assets/sprites/%s\" % img\n",
     NOTE + "\tvar pet: Dictionary = PetUiIdle.of(DataRegistry.pet_by_id.get(id, {}))\n\tvar img := str(pet.get(\"img\", \"\"))\n\tvar path := \"res://assets/sprites/%s\" % img\n"),
])
print("ok")
