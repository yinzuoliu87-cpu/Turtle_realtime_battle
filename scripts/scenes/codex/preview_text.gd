extends RefCounted
## 图鉴龟页的「预览」文字: 一行条(被动条 / 普通攻击条)与技能卡上的简述(2026-10-10)。
## 纯静态, 不持状态。用法: const PreviewText := preload("res://scripts/scenes/codex/preview_text.gd")
##
## 两件事:
##  ① 简述开头若是一行只有小标题(「登场轰击：」「主被动·潜影：」), 预览就只剩这个标题 ——
##     海盗龟被动条实拍只有「登场轰击：」四个字。⇒ 预览从标题下面那句真正的效果开始。
##  ② 一行条放不下时, 原来是 clip 硬切(小龟「…技能与真实伤」), 读不出被切了。
##     ⇒ 按【渲染后真实的第一行】在字边界处截断, 末尾加「…」; BBCode 标签不切开、开着的标签补齐闭合。

## 小标题行的可见字数上限。实测最长的是「主被动·潜影：」(7 字); 12 给一点余量, 又不至于把一句短正文当成标题。
const HEAD_MAX := 12
## 截断时末尾去掉的软标点(「，…」「。…」不如直接「…」)。
const SOFT_TAIL := "，、；：。,;: "

## 一行源文案(含 <span>/<img> 标签)的可见文字。
static func plain_of(line: String) -> String:
	var out := ""
	var i := 0
	while i < line.length():
		if line[i] == "<":
			var gt := line.find(">", i)
			if gt < 0:
				out += line.substr(i)
				break
			i = gt + 1
		else:
			out += line[i]
			i += 1
	return out.strip_edges()

## 「只有一个小标题」的一行: 以全角/半角冒号收尾、而且很短。
static func is_heading_line(plain: String) -> bool:
	var t := plain.strip_edges()
	return t.length() >= 2 and t.length() <= HEAD_MAX and (t.ends_with("：") or t.ends_with(":"))

## 一行里所有标签原样拼起来(丢掉可见字)。
static func _tags_of(line: String) -> String:
	var out := ""
	var i := line.find("<")
	while i >= 0:
		var gt := line.find(">", i)
		if gt < 0:
			break
		out += line.substr(i, gt - i + 1)
		i = line.find("<", gt + 1)
	return out

## ① 跳过开头那几行纯小标题。只删它们的可见字, 标签保留 —— span 常常跨行
##   (石头龟「<span 灰>被动：\n石头龟每次…</span>」), 删掉开标签会让后面的闭标签落空。
## 至少留一行正文: 全是标题(不该有)时原样返回。
static func skip_lead_headings(src: String) -> String:
	var lines := src.split("\n")
	var k := 0
	var tags := ""
	while k < lines.size() - 1 and is_heading_line(plain_of(lines[k])):
		tags += _tags_of(lines[k])
		k += 1
	if k == 0:
		return src
	return tags + "\n".join(lines.slice(k))

## BBCode 截到前 n 个可见字(一个 [img] 算 1 个), 去掉切口处的软标点, 加「…」, 再把还开着的标签依次闭合。
static func bb_cut(bb: String, n: int) -> String:
	var out := ""
	var stack: Array = []
	var cnt := 0
	var i := 0
	while i < bb.length() and cnt < n:
		var c := bb[i]
		if c == "[":
			var rb := bb.find("]", i)
			if rb < 0:
				break
			var tag := bb.substr(i + 1, rb - i - 1)
			if tag.begins_with("img"):
				var close := bb.find("[/img]", rb)
				if close < 0:
					break
				out += bb.substr(i, close + 6 - i)
				cnt += 1
				i = close + 6
				continue
			if tag.begins_with("/"):
				if not stack.is_empty():
					stack.pop_back()
			else:
				stack.append(tag.split(" ")[0].split("=")[0])
			out += bb.substr(i, rb - i + 1)
			i = rb + 1
			continue
		if c == "\n":
			break   # 一行预览: 换行就是这一行的尽头
		out += c
		cnt += 1
		i += 1
	## 切口处若紧跟一个可见字之后就是软标点/空白, 去掉它再加省略号(只动可见字, 不动标签)。
	while out.length() > 0 and SOFT_TAIL.contains(out[out.length() - 1]):
		out = out.substr(0, out.length() - 1)
	out += "…"
	for j in range(stack.size() - 1, -1, -1):
		out += "[/%s]" % str(stack[j])
	return out

## ② 把 bb 塞进一个定高一行的 RichTextLabel: 放得下就原样, 放不下就截成「一行 + …」。返回是否截断了。
## ★「放得下」= 只有一行【并且】没有被换行符藏起来的后文(简述常是两段, 第二段整个看不见也算被截)。
## ★RichTextLabel 不开 threaded 时排版是同步的: 刚改完 text 就问 get_line_count() 拿到的是新排版(探针实测)。
static func fit_one_line(rt: RichTextLabel, bb: String) -> bool:
	rt.text = bb
	var has_more: bool = rt.get_parsed_text().strip_edges().contains("\n")
	if rt.get_line_count() <= 1 and not has_more:
		return false
	var n: int = rt.get_line_range(0).y + 1
	while n > 0:
		rt.text = bb_cut(bb, n)
		if rt.get_line_count() <= 1:
			return true
		n -= 1
	return true
