# -*- coding: utf-8 -*-
"""tools/assetgen/sfx_v2_table.py — 音效 v2 描述表生成器(2026-11-05 · 全部重做, 对标云顶 / LoL)。
由来: 用户 11-05「你音效是死贴着像素吗，跟云顶学啥了」「旧的那个普攻、伤害音效、盾音效，全部都要重做，全部都要达到云顶的标准」
  「云顶音效怎么做的？每个技能怎么做的这个音效？你怎么做出它的效果？」
云顶 / LoL 的做法(实拆游戏文件, tools/oneoff/riot_audio_extract.py; 记录 docs/studies/20261105-云顶音效拆解-科加斯Q声轨逐帧.md):
  ① 一个动作按时刻拆成几条: 普攻 = 出手(OnCast) + 命中(OnHit), 暴击另一套; 技能 = 放出(OnCast) + 命中(hit / OnHitLocation)
     [+ 弹道 / 增益开始 / 结束]; 装备、护盾、治疗、阵亡各有自己的一条。
  ② 高频的(普攻出手 / 命中)每条 3~4 个变体随机轮换, 技能命中 2~3 个。
  ③ 每个英雄一套材质(科加斯 = 血肉 + 岩石 + 低吼), 所有技能共用这套材质, 听得出是谁。
  ④ 声音本身: 低频有分量(150 Hz 以下占 1/3)、有声段密(RMS 比我们高 ~8 dB)、质感是噪声型拟音(不是纯音 / 方波)。
本脚本把这些写成表: 每条 = 事件名 / 中文 / 秒数 / 候选数 / 参考的 Riot 事件 / 英文描述。
  产物 tools/assetgen/sfx_prompts_v2.json(gen_sfx_elevenlabs.py --prompts 读)。重跑逐字节相同。
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "tools", "assetgen", "sfx_prompts_v2.json")

STYLE = ("High-fidelity fantasy MOBA game sound effect in the style of League of Legends and Teamfight Tactics, "
	"professionally layered, punchy transient, full-bodied low end, crisp detail, tight and clean, no music, no speech")

# ── 每只龟: 材质 / 近远程 / 普攻出手 / 普攻命中 / 暴击 / 参考英雄 ───────────────────────────────
# 出手(bas) = 近战挥击的破风或远程的发射声; 命中(bah) = 打在敌人身上那一下; 暴击(crit) = 更重的一层。
T = {
	"basic": dict(zh="小龟", ref="LeeSin/Udyr", mat="martial arts chi energy, cloth and fists",
		bas="a fast martial arts punch swing, sharp cloth whoosh with a faint chi hum",
		bah="a meaty martial arts fist impact on a body, solid thump with a short chi crackle",
		crit="a devastating chi-charged punch, deep body thud with a bursting energy crack"),
	"stone": dict(zh="石头龟", ref="Malphite", mat="heavy granite rock, gravel and earth",
		bas="a heavy stone fist swung through the air, low weighty whoosh with pebbles rattling",
		bah="a huge stone fist crushing into an enemy, deep rocky crunch with gravel debris",
		crit="a massive boulder smash, earth-shaking stone crack with a sub-bass thud and falling rubble"),
	"bamboo": dict(zh="竹叶龟", ref="Ivern/Maokai", mat="bamboo wood, leaves and vines",
		bas="a bamboo staff swung fast, hollow wooden swish with rustling leaves",
		bah="a bamboo staff striking an enemy, crisp hollow wooden crack with a leafy rustle",
		crit="a heavy bamboo staff smash, splintering wooden crack with a deep knock and scattering leaves"),
	"angel": dict(zh="天使龟", ref="Kayle", mat="holy light, feathers and celestial bells",
		bas="a small orb of holy light launched, soft feathery whoosh with a bright celestial shimmer",
		bah="a holy light bolt striking an enemy, radiant burst with a clear angelic ring and a soft thump",
		crit="a searing holy smite, bright radiant explosion with a choir-like shimmer and a heavy thump"),
	"ice": dict(zh="寒冰龟", ref="Lissandra/Anivia", mat="ice crystals, frost and cold wind",
		bas="an ice shard fired, sharp icy whistle with a crackling frost trail",
		bah="an ice shard shattering on an enemy, crisp ice crack with tinkling crystal fragments",
		crit="a large ice spike impaling an enemy, heavy ice shatter with a deep cold thud and frost burst"),
	"ninja": dict(zh="忍者龟", ref="Zed/Akali", mat="steel blades, shadow and quick cloth",
		bas="a ninja katana slash swing, razor-sharp metallic whoosh",
		bah="a katana slicing through an enemy, sharp steel cut with a quick fleshy slice",
		crit="a lethal katana strike, ringing steel slash with a deep cutting impact and a shadowy whoosh"),
	"two_head": dict(zh="变脸龟", ref="Jayce", mat="psychic energy and a heavy hextech hammer",
		bas="a psionic energy bolt fired, warbling energy whoosh with an electric hum",
		bah="a psionic energy bolt impact, punchy energy burst with a warbling electric crackle",
		crit="a heavy psionic blast, deep energy explosion with distorted warble and a bass thump"),
	"ghost": dict(zh="幽灵龟", ref="Hecarim/Thresh", mat="spectral wind, ghostly whispers and soul fire",
		bas="a ghostly wisp launched, eerie hollow whoosh with a breathy spectral tail",
		bah="a spectral wisp striking an enemy, cold ghostly impact with a hollow echo",
		crit="a soul-tearing spectral strike, deep haunted impact with a ghostly wail and dark echo"),
	"diamond": dict(zh="钻石龟", ref="Taric/Rammus", mat="diamond, gemstone and polished crystal",
		bas="a diamond-edged claw swipe, glassy whoosh with a faint crystal ring",
		bah="a diamond blade cutting an enemy, sharp glassy slice with a bright gem ring and solid thud",
		crit="a heavy diamond smash, crystal shattering crunch with a deep thud and ringing shards"),
	"fortune": dict(zh="财神龟", ref="TwistedFate/Gangplank", mat="gold coins, gold metal and lucky chimes",
		bas="a golden sword swing, metallic whoosh with a soft coin jingle",
		bah="a golden sword striking an enemy, solid metal hit with a bright coin clink",
		crit="a heavy golden strike, deep metallic clang with a burst of jingling coins"),
	"dice": dict(zh="骰子龟", ref="Darius/Irelia", mat="heavy dark steel scythe and tumbling bone dice",
		bas="a heavy scythe blade swung, deep sharp metallic whoosh",
		bah="a scythe blade slashing an enemy, heavy steel cut with a meaty impact",
		crit="a brutal scythe slash, heavy metal cleave with a bone-crunching thud and a ringing blade"),
	"rainbow": dict(zh="彩虹龟", ref="Lux/Seraphine", mat="prismatic light, crystal chimes and shimmering magic",
		bas="a prismatic light beam fired, bright shimmering zap with a sparkling whoosh",
		bah="a prismatic beam striking an enemy, bright magical burst with sparkling chimes",
		crit="a dazzling prismatic blast, bright magic explosion with layered sparkling chimes and a punchy thud"),
	"gambler": dict(zh="赌神龟", ref="TwistedFate", mat="magic playing cards, card flicks and arcane shimmer",
		bas="a magic playing card thrown, sharp card flick with a fast arcane whoosh",
		bah="a magic card slicing into an enemy, crisp paper slap with an arcane pop",
		crit="a charged magic card strike, sharp arcane burst with a heavy card slap and a sparkle"),
	"hunter": dict(zh="猎人龟", ref="Ashe/Vayne/Varus", mat="wooden longbow, bowstring and arrows",
		bas="a longbow firing an arrow, tight bowstring twang with a fast arrow whoosh",
		bah="an arrow striking an enemy, solid arrow thunk into a body",
		crit="a powerful arrow piercing an enemy, heavy thunk with a sharp crack and a whistling tail"),
	"pirate": dict(zh="海盗龟", ref="Gangplank/MissFortune", mat="steel cutlass, gunpowder and ship timber",
		bas="a pirate cutlass swing, quick steel whoosh",
		bah="a cutlass slashing an enemy, sharp steel hit with a meaty cut",
		crit="a brutal cutlass slash, ringing steel cleave with a heavy impact and a gunpowder crack"),
	"candy": dict(zh="糖果龟", ref="Gragas/Gnar", mat="hard candy, sugar glass and sticky caramel",
		bas="a fist coated in hard candy swung, quick whoosh with a sugary crackle",
		bah="a candy-coated fist smashing an enemy, crunchy sugar-glass crack with a solid body thump",
		crit="a heavy candy smash, big crunchy sugar-glass shatter with a deep thud and sticky splat"),
	"bubble": dict(zh="泡泡龟", ref="Nami/Zac", mat="water, bubbles and liquid splashes",
		bas="a water bubble launched, wet bubbly whoosh",
		bah="a water bubble bursting on an enemy, wet splashy pop with a liquid impact",
		crit="a large water bubble exploding on an enemy, heavy splash burst with a deep watery thud"),
	"line": dict(zh="线条龟", ref="Hwei", mat="ink, brush strokes and paper",
		bas="a fast ink brush stroke flicked, swishing brush whoosh with wet ink",
		bah="an ink stroke slashing an enemy, wet ink splatter with a crisp brush slap",
		crit="a heavy ink brush strike, big wet ink splash with a sharp slap and dark resonance"),
	"lightning": dict(zh="闪电龟", ref="Zeri/Kennen", mat="electricity, thunder and static",
		bas="a lightning bolt fired, sharp electric zap with crackling static",
		bah="a lightning bolt striking an enemy, loud electric crack with a buzzing static burst",
		crit="a massive lightning strike, thunderous electric crack with a deep boom and sizzling static"),
	"phoenix": dict(zh="凤凰龟", ref="Anivia/Brand/Annie", mat="fire, flames and embers",
		bas="a short burst of fire breath, roaring flame whoosh",
		bah="flames scorching an enemy, fiery burst with a hot crackling sizzle",
		crit="a blazing fire blast, explosive flame burst with a deep whump and crackling embers"),
	"lava": dict(zh="熔岩龟", ref="Brand/Malphite", mat="molten lava, magma rock and fire",
		bas="a molten lava fist swung, heavy fiery whoosh with a magma sizzle",
		bah="a molten fist smashing an enemy, heavy rocky impact with a hot lava sizzle",
		crit="a massive molten slam, deep rock crunch with a magma splash and a fiery boom"),
	"cyber": dict(zh="赛博龟", ref="Viktor/Zeri", mat="sci-fi laser, servo motors and electronic energy",
		bas="a sci-fi laser rifle fired, crisp energy blast with an electronic whine",
		bah="a laser beam hitting an enemy, searing energy burst with an electric sizzle",
		crit="a high-power laser blast, heavy energy explosion with a deep electronic boom"),
	"crystal": dict(zh="水晶龟", ref="Taliyah/Skarner", mat="resonant crystal, quartz and stone",
		bas="a crystal spike thrust, resonant crystal whoosh",
		bah="a crystal spike stabbing an enemy, sharp crystalline crack with a ringing resonance",
		crit="a heavy crystal spike impaling an enemy, loud crystal shatter with a deep resonant thud"),
	"chest": dict(zh="宝箱龟", ref="KSante", mat="heavy wooden treasure chest, iron bands and gold",
		bas="a heavy treasure chest swung, weighty wooden whoosh with rattling coins",
		bah="a treasure chest slamming an enemy, heavy wooden thud with iron clank and coin rattle",
		crit="a crushing treasure chest slam, huge wooden crash with an iron clang and spilling gold"),
	"space": dict(zh="星际龟", ref="AurelionSol/Zoe", mat="cosmic starlight, deep space and gravity",
		bas="a starlight bolt launched, sparkling cosmic whoosh with a soft deep hum",
		bah="a starlight bolt striking an enemy, sparkling cosmic burst with a deep resonant thump",
		crit="a supernova strike, bright cosmic explosion with a deep gravitational boom and sparkles"),
	"hiding": dict(zh="缩头乌龟", ref="Rammus/Shen", mat="hard turtle shell and armor",
		bas="a hard shell bash wind-up, short heavy whoosh",
		bah="a hard turtle shell bashing an enemy, solid hollow shell knock with a body thump",
		crit="a heavy shell slam, deep hollow armored crash with a strong low thud"),
	"headless": dict(zh="无头龟", ref="Chogath/Mordekaiser", mat="monstrous flesh, bone and dark energy",
		bas="a monstrous lunge, guttural fleshy whoosh",
		bah="a monstrous bite tearing into an enemy, wet crunching chomp with bone crack",
		crit="a savage monster bite, brutal wet crunch with a deep bone snap and a dark growl"),
	"shell": dict(zh="龟壳", ref="KogMaw/Corki", mat="dark shell, shadow magic and hollow resonance",
		bas="a dark shell strike wind-up, hollow shadowy whoosh",
		bah="a shadow-charged shell strike hitting an enemy, hollow knock with a dark magical pulse",
		crit="a heavy shadow shell strike, deep hollow crash with a dark resonant boom"),
}
MELEE = {"dice", "ninja", "bamboo", "basic", "headless", "pirate", "two_head", "candy", "lava", "rainbow", "chest",
	"fortune", "crystal", "diamond", "hiding", "shell", "stone"}

# ── 每个技能: 放出(cast) / 命中(hit, 不造成伤害的技能没有) / 秒数 / 参考 Riot 技能 ───────────────────────
# 键 = 技能类型(stype); 熔岩龟火山形态三条另列。描述照该技能的特效与机制写(竹刺阵 = 科加斯 Q: 先地鸣蓄力, 0.6 秒后竹刺破土)。
S = [
	("basicBarrage", "小龟·打击", 1.4, "LeeSin Q", "a rapid flurry of chi energy blasts fired one after another, each a punchy energy pop with a whoosh, building intensity",
		"a chi energy blast exploding on an enemy, punchy energy burst with a body thump"),
	("basicChiWave", "小龟·龟派气波", 2.0, "Ezreal R", "a martial artist charging a huge chi energy wave, rising powerful energy hum building up, then a massive energy beam blast released with a roaring whoosh",
		"a huge chi energy wave crashing through an enemy, powerful energy impact with a roaring rush"),
	("basicSlam", "小龟·过肩摔", 1.6, "LeeSin R", "a grappler grabbing an enemy, cloth grab and a fast spinning whoosh as the body is lifted overhead",
		"a body slammed hard into the ground, massive earth-shaking thud with a crunchy impact and dust"),
	("stoneRockShield", "石头龟·岩石护盾", 1.4, "Malphite W/passive", "heavy rocks and stone plates grinding and locking together into a protective stone shield, deep earthy rumble ending in a solid stone clunk", None),
	("rockShockwave", "石头龟·磐石之躯", 1.6, "Malphite E", "a stone giant stomping the ground, a heavy rock shockwave cracking outward with a deep earthquake rumble",
		"a rock shockwave launching an enemy into the air, heavy stone crunch with gravel debris"),
	("stoneTaunt", "石头龟·嘲讽", 1.8, "Malphite R", "a stone giant bellowing a deep war drum boom, then charging up and slamming down with a massive ground-shattering rock impact",
		"a massive rock slam knocking an enemy up, heavy stone crack with rumbling debris"),
	("bambooHeal", "竹叶龟·自然恢复", 1.6, "Ivern W", "nature healing magic blooming, gentle rustling leaves with a soft rising magical shimmer and a warm wooden chime", None),
	("bambooSmack", "竹叶龟·竹击", 1.5, "Maokai W/Ivern Q", "a long bamboo vine lashing out fast, sharp whip crack then a creaking wooden yank pulling something in",
		"a bamboo vine snaring and yanking an enemy, sharp woody crack with a heavy pull thud"),
	("bambooSpikes", "竹叶龟·竹刺阵", 1.6, "Chogath Q", "a deep ominous underground rumble building, the earth cracking and swelling as something is about to erupt from below",
		"dozens of sharp bamboo spikes violently erupting out of the ground, explosive earth burst with splintering wooden stabs and rocks flying"),
	("angelBless", "天使龟·祝福", 1.8, "Kayle R", "a holy blessing descending, rising heavenly choir-like shimmer with bright bells and soft feathery wings", None),
	("angelEquality", "天使龟·平等", 1.6, "Kayle E", "three radiant holy light blades slashing in quick succession, bright ringing swishes with celestial shimmer",
		"a holy light blade cutting an enemy, radiant slash with a bright ringing impact"),
	("angelAscend", "天使龟·飞升", 1.8, "Kayle passive ascend", "an angel ascending in power, big rising whoosh of wings with a radiant holy swell and bright shimmer", None),
	("iceFrost", "寒冰龟·冰霜", 1.6, "Lissandra W/Anivia R", "a freezing blizzard field forming, icy wind gust with crackling frost and tinkling ice crystals",
		"freezing frost biting an enemy, crisp ice crack with a cold hiss"),
	("iceFreeze", "寒冰龟·冰封", 1.4, "Lissandra R", "a target instantly frozen solid, ice rapidly encasing with a sharp crystalline crack and deep cold resonance",
		"an enemy encased in ice, loud ice crack with a heavy frozen thud"),
	("commonTeamShield", "寒冰龟·团队护盾", 1.4, "Janna E/Lulu E", "a protective frost barrier forming over allies, soft rising icy shimmer with a clear crystalline chime", None),
	("ninjaShuriken", "忍者龟·手里剑", 1.2, "Shen/Zed Q", "a large shuriken thrown, sharp spinning metal whir cutting through the air",
		"a spinning shuriken slicing an enemy, sharp metallic cut with a ringing steel tail"),
	("ninjaBomb", "忍者龟·炸弹", 1.4, "Akali W/Ziggs", "a ninja smoke bomb tossed, short fuse hiss then a punchy explosion with a smoke puff",
		"a ninja bomb blast hitting an enemy, punchy explosion with debris"),
	("ninjaBackstab", "忍者龟·背刺", 1.2, "Zed W/Akali R", "a ninja vanishing in a shadow blink and reappearing behind the target, dark whoosh and a quick blade draw",
		"a ninja blade stabbing deep into an enemy, sharp steel stab with a heavy impact"),
	("twoHeadStrike", "变脸龟·灵能冲击/锤击", 1.6, "Jayce Q / Jayce hammer Q", "psionic energy charging into a powerful blast, warbling energy build-up released as a heavy shockwave boom",
		"a heavy psionic hammer blow smashing an enemy, deep energy explosion with a metallic crunch"),
	("twoHeadDisrupt", "变脸龟·精神干扰", 1.4, "Malzahar W/Swain", "a disorienting psychic wave, eerie warbling distortion with a glitchy mental pulse",
		"a psychic pulse rattling an enemy's mind, warbling distorted zap with a dull thump"),
	("twoHeadFusion", "变脸龟·融合", 1.8, "Jayce R transform", "two energies fusing into a transformation, mechanical shifting with a rising psionic hum resolving into a powerful pulse", None),
	("ghostPhantom", "幽灵龟·幽冥突袭", 1.4, "Hecarim E/Thresh", "a spectral lunge, rushing ghostly wind with eerie whispers and a hollow echo",
		"a phantom striking an enemy, cold spectral impact with a ghostly wail"),
	("ghostStorm", "幽灵龟·灵魂风暴", 1.8, "Karthus/Yorick", "a swirling soul storm forming, howling ghostly wind vortex with distant wails building",
		"souls tearing into an enemy, dark spectral burst with a haunting echo"),
	("ghostPhase", "幽灵龟·虚化", 1.4, "Hecarim/Kassadin", "turning ethereal and intangible, reverse ghostly whoosh fading into a shimmering hollow resonance", None),
	("diamondFortify", "钻石龟·坚不可摧", 1.4, "Taric W", "diamond armor forming, crystal plates clinking together into a hard glassy shield ring with a solid low hum", None),
	("diamondPowerball", "钻石龟·钻石滚球", 1.8, "Rammus Q", "a diamond ball curling up and rolling faster and faster, heavy accelerating rumble with crystal grinding",
		"a rolling diamond ball crashing into an enemy, heavy crystal impact with a deep crunch"),
	("diamondSmash", "钻石龟·钻石冲撞", 1.5, "Taric/Rammus", "a crystal body charging forward, heavy rush with a glassy ring",
		"a crystal body slam into an enemy, heavy glassy crash with shattering shards"),
	("fortuneDice", "财神龟·骰子", 1.4, "TwistedFate W", "golden dice rattling and tossed onto the ground, bright golden tumble with a lucky chime",
		"a golden dice blast striking an enemy, bright metallic impact with jingling gold"),
	("fortuneAllIn", "财神龟·梭哈", 1.8, "Gangplank/MissFortune R", "a barrage of gold coins flung out rapidly, a stream of metallic coin whooshes and clinks",
		"gold coins pelting an enemy, rapid metallic coin hits with a solid thump"),
	("fortuneBuyEquip", "财神龟·招财进宝", 1.4, "TFT gold", "a satisfying gold purchase, bright cash register cha-ching with a magical golden shimmer", None),
	("diceAllIn", "骰子龟·孤注一掷", 1.2, "Darius Q", "a huge scythe swept in a full circle, deep heavy whoosh with a sharp metallic edge",
		"a scythe blade cleaving an enemy, heavy steel slash with a meaty impact"),
	("diceFate", "骰子龟·命运骰子", 1.4, "TwistedFate W", "magic dice rolled, bone dice tumbling then a glowing magical resonance",
		"a fate die bursting on an enemy, magical impact with a rattle"),
	("diceFlashStrike", "骰子龟·稳定骰子", 1.2, "Irelia Q", "a lightning-fast blade dash, sharp rushing whoosh with a ringing blade",
		"a dashing blade strike through an enemy, crisp steel slash with a fast impact"),
	("shield", "彩虹龟·棱镜护盾", 1.4, "Lux W", "a prismatic shield forming, bright crystalline rainbow shimmer swelling into a clear resonant chime", None),
	("rainbowStorm", "彩虹龟·全色风暴", 2.0, "Lux R/Seraphine R", "a swirling prismatic storm building, whirling magical wind with bright layered sparkling tones and a powerful swell",
		"prismatic energy blasting an enemy, bright magic burst with sparkles"),
	("rainbowReflect", "彩虹龟·反射", 1.2, "Lux/Taric", "a prism catching light, bright glassy ping and refracting shimmer",
		"reflected prismatic light striking an enemy, bright glassy zap"),
	("gamblerDraw", "赌神龟·万能牌", 1.2, "TwistedFate Q", "a magic card drawn and flicked, sharp card snap with an arcane whoosh",
		"a magic card exploding on an enemy, arcane pop with a crisp card slap"),
	("gamblerBet", "赌神龟·赌注", 1.6, "TwistedFate Q", "a fan of magic cards thrown, rapid card shuffle and multiple card flicks whooshing out",
		"magic cards slicing into an enemy, several crisp card hits with an arcane sparkle"),
	("gamblerFateWheel", "赌神龟·命运之轮", 1.8, "TwistedFate R", "a magic roulette wheel spinning, rapid ratcheting clicks slowing down then a bright magical ding",
		"a fortune burst striking an enemy, arcane impact with a bright ring"),
	("hunterShot", "猎人龟·精准射击", 1.4, "Varus Q/Ashe W", "a longbow drawn slowly with a creaking bowstring, then a powerful arrow release with a deep twang",
		"a powerful arrow piercing an enemy, heavy thunk with a ringing tail"),
	("hunterStealth", "猎人龟·隐蔽", 1.0, "Vayne Q", "a quick tumble roll, fast cloth whoosh with a light footstep and a stealthy shimmer", None),
	("hunterBarrage", "猎人龟·狩猎弹幕", 1.6, "Ashe W/Varus", "a volley of arrows fired at once, layered bowstring twangs and many arrows whistling out",
		"arrows raining into an enemy, several solid arrow thunks"),
	("pirateCannonBarrage", "海盗龟·火炮齐射", 2.0, "Gangplank R", "a pirate ship cannon barrage, several booming cannon shots with whistling cannonballs",
		"a cannonball exploding on impact, heavy gunpowder explosion with wood and debris"),
	("pirateRum", "海盗龟·朗姆酒", 1.4, "Gangplank W", "a glass rum bottle uncorked and gulped, liquid slosh then a refreshing healing shimmer", None),
	("pirateShipPassive", "海盗龟·海盗船", 1.8, "Gangplank/Pyke", "a pirate ship ramming forward, creaking ship timber with a rushing wave",
		"a pirate ship crashing into an enemy, heavy wooden crash with a splashing wave"),
	("candyHammer", "糖果龟·糖果锤", 1.6, "Gragas E/Poppy", "a giant candy hammer raised, heavy wind-up whoosh then a crushing smash",
		"a giant candy hammer smashing enemies, crunchy sugar-glass shatter with a deep thud"),
	("candyBarrage", "糖果龟·糖衣炮弹", 2.0, "Gangplank R", "a rain of candy-coated bombs falling from the sky, whistling bombs and a sequence of sugary explosions",
		"a candy bomb exploding on impact, crunchy sugary explosion with a sticky splat"),
	("candyBomb", "糖果龟·糖果炸弹", 1.6, "Ziggs R", "a candy bomb's fuse fizzing, sugary sizzle building to a big explosion",
		"a candy bomb explosion hitting enemies, crunchy sugar blast with debris"),
	("bubbleShield", "泡泡龟·泡泡盾", 1.4, "Nami/Lulu E", "a protective water bubble forming around an ally, wobbly liquid swell with a soft resonant pop", None),
	("bubbleBind", "泡泡龟·泡泡束缚", 1.4, "Nami Q", "a big water bubble launched, wet whoosh",
		"a water bubble trapping an enemy, gloopy splash with a wobbly bubble swell"),
	("bubbleBurst", "泡泡龟·泡泡爆破", 1.6, "Malzahar Q/Nami", "many bubbles swelling then bursting at once, rapid wet pops and a big splash",
		"a bubble bursting on an enemy, wet splashy pop with a liquid impact"),
	("lineLink", "线条龟·连笔", 1.4, "Hwei", "an ink brush drawing a long line, fast brush swish with a wet stretching ink tether",
		"an ink tether lashing an enemy, wet ink snap with a brush slap"),
	("lineFinish", "线条龟·画龙点睛", 1.6, "Hwei R", "a decisive final brush stroke, sweeping ink swish then a heavy ink dot slam",
		"a heavy ink strike on an enemy, big wet ink splash with a sharp impact"),
	("lineInkBomb", "线条龟·墨水炸弹", 1.4, "Hwei", "an ink bomb thrown, wet whoosh",
		"an ink bomb exploding, wet gloopy ink splatter burst"),
	("lightningSurgeBuff", "闪电龟·涌动", 1.4, "Zeri W/Kennen E", "an electric surge empowering, crackling static charging up into a sharp electric zap", None),
	("lightningBarrage", "闪电龟·雷暴", 2.0, "Kennen R/Zeri R", "a thunderstorm unleashed, several thunder cracks and electric bolts striking down in quick succession",
		"a lightning bolt striking an enemy, loud electric crack with sizzling static"),
	("lightningShield", "闪电龟·雷盾", 1.4, "Kennen/Zeri", "an electric shield forming, buzzing static field crackling around the body", None),
	("phoenixShield", "凤凰龟·熔岩盾", 1.4, "Anivia/Brand", "a fiery shield igniting, flames roaring into a burning barrier", None),
	("phoenixScald", "凤凰龟·烫伤", 1.4, "Brand Q/Annie Q", "a fireball hurled, roaring fiery whoosh",
		"a fireball exploding on an enemy, fiery burst with a hot sizzle and crackling embers"),
	("phoenixEnhancedRebirth", "凤凰龟·强化涅槃", 2.0, "Anivia passive rebirth", "a phoenix reborn from its egg, a huge burst of rising flames with a mighty fiery roar", None),
	("lavaQuake", "熔岩龟·地裂", 1.6, "Brand W", "the ground cracking open, a magma pool bubbling up with a deep rumble and a fiery hiss",
		"lava scorching an enemy, hot sizzle with a molten bubble pop"),
	("lavaSurge", "熔岩龟·岩浆涌动", 1.6, "Brand W/Malphite", "a magma geyser erupting from the ground, explosive lava burst with flying molten rock",
		"a magma geyser blasting an enemy, heavy molten impact with sizzle"),
	("lavaErupt", "熔岩龟·熔岩爆发", 1.6, "Lux R/Brand", "a searing lava beam fired, roaring molten blast with a deep fiery rumble",
		"a lava beam burning through an enemy, searing hot impact with a molten splash"),
	("volcanoErupt", "火山龟·火山爆发", 2.2, "Nami R", "a massive lava wave rushing forward, a roaring tide of molten rock with deep rumbling and fiery crashes",
		"a lava wave crashing over an enemy, heavy molten surge impact with sizzle"),
	("volcanoSmash", "火山龟·重击", 1.6, "Malphite Q", "a volcanic fist wind-up, heavy fiery whoosh",
		"a volcanic slam crushing an enemy, deep molten rock impact with a fiery boom"),
	("lavaRampage", "火山龟·烈焰暴走", 1.8, "Brand R/Malphite", "a volcanic rage awakening, roaring flames and deep rumbling heat building into a fiery roar", None),
	("cyberBeam", "赛博龟·能量大炮", 2.0, "Viktor E/Xerath R", "a sci-fi energy cannon charging with a rising electronic whine, then a massive laser beam blast",
		"a laser beam searing an enemy, heavy energy impact with an electric sizzle"),
	("cyberHijack", "赛博龟·侵入", 1.4, "Viktor/Camille", "a digital hacking intrusion, glitchy data stutters and a dark electronic takeover tone", None),
	("cyberSmartAI", "赛博龟·智能AI", 1.4, "Camille/Viktor", "a combat AI activating, servo motors whirring with digital beeps and a thruster burst", None),
	("crystalBarrier", "水晶龟·水晶壁垒", 1.6, "Taliyah E/Skarner", "a crystal wall rising from the ground, grinding stone with resonant glassy hum and crystal clinks", None),
	("crystalBurst", "水晶龟·碎晶爆破", 1.4, "Skarner/Taliyah", "crystal shards exploding outward, loud glass shatter burst",
		"crystal shards piercing an enemy, sharp crystalline cracks with a ringing resonance"),
	("crystalBall", "水晶龟·水晶球", 1.6, "Orianna/Syndra", "a crystal orb summoned, mystical glassy ring humming then a beam zap",
		"a crystal beam striking an enemy, resonant crystal zap with a sharp crack"),
	("chestCount", "宝箱龟·清点财宝", 1.4, "TFT loot", "a treasure chest creaking open, coins and jewels clinking with a warm healing shimmer", None),
	("chestStorm", "宝箱龟·财宝风暴", 2.0, "KSante/Gangplank", "a whirlwind of gold coins and gems, swirling wind with layered metallic jingles",
		"gold and gems striking an enemy, metallic clinks with a solid thump"),
	("chestCannon", "宝箱龟·财宝炮击", 1.6, "Gangplank", "a treasure cannon firing, heavy cannon boom with a spray of coins",
		"a treasure cannon shot exploding on an enemy, heavy blast with scattering coins"),
	("starWormhole", "星际龟·虫洞", 2.0, "Orianna R", "a wormhole opening, deep sci-fi warping whoosh with a powerful gravitational hum pulling inward",
		"cosmic gravity crushing an enemy, deep warping impact with a resonant boom"),
	("starWave", "星际龟·星波", 1.8, "AurelionSol R", "a falling star crashing down, bright cosmic whoosh into a sparkling shockwave",
		"a star wave blasting an enemy, sparkling cosmic impact with a deep boom"),
	("starGravityWarp", "星际龟·扭曲空间", 2.0, "Bard R/Zoe", "space bending and warping, deep distorted whoosh collapsing into a heavy implosion",
		"warped space crushing an enemy, deep implosion impact"),
	("hidingShrink", "缩头乌龟·缩头", 1.2, "Rammus W", "a turtle retreating into its hard shell, quick hollow shell clunk and an armored thud", None),
	("hidingDefend", "缩头乌龟·防御", 1.4, "Rammus W/Shen", "a sturdy defensive stance, heavy shell armor clank with a deep protective hum", None),
	("hidingBuffSummon", "缩头乌龟·强化随从", 1.4, "Shen R/Lulu", "empowering an ally, rising golden power-up swell with a bright resonant chime", None),
	("headlessFear", "无头龟·恐吓", 1.6, "Chogath W", "a terrifying monstrous roar shockwave, horrifying growl with a deep dark boom",
		"a fear wave hitting an enemy, dark impact with a ghostly shriek"),
	("headlessTendrils", "无头龟·万千触须", 2.0, "Chogath Q/Illaoi", "dozens of fleshy tentacles bursting out of the ground, squelching wet whips with a deep monstrous rumble",
		"a fleshy tentacle whipping an enemy, wet slap with a meaty crunch"),
	("headlessSoulStrike", "无头龟·灵魂打击", 1.4, "Mordekaiser/Yorick", "dark soul power empowering a blade, eerie ghostly hum with a scraping blade sharpening", None),
	("shellCopy", "龟壳·复制", 1.4, "Neeko/LeBlanc", "a magical copy forming, mirror shimmer with an echoing whoosh", None),
	("shellAbsorb", "龟壳·吸收", 1.4, "Vladimir/Fiddlesticks W", "a life drain beam, dark sucking whoosh with a pulsing heartbeat",
		"life force ripped from an enemy, dark draining pulse with a wet suck"),
	("shellShadow", "龟壳·暗影", 1.6, "Corki W", "a shadowy dive, dark rushing whoosh with a fading shadow shimmer",
		"a shadow strike hitting an enemy, dark hollow impact"),
]

# ── 装备: 只配有「触发那一刻」的; 纯属性(047 / 054 / 085 …)不出声(云顶同理) ─────────────────────────
E = [
	("p2eq_001", "木制长剑·剑气", "a wooden sword unleashing a sword wave, sharp slicing whoosh with a wooden crack"),
	("p2eq_004", "暴君之牙·处决/毒牙", "a venomous fang shot, sharp hiss with a vicious bite"),
	("p2eq_005", "双生匕首·追加刺击", "a quick extra dagger stab, sharp steel stab"),
	("p2eq_006", "千刃风暴", "a row of conjured swords sweeping across the battlefield, many ringing blades whooshing past"),
	("p2eq_007", "锈蚀阔剑·剑气墙", "a rusty broadsword unleashing a piercing wall of sword energy, heavy grinding steel whoosh"),
	("p2eq_008", "双穿珊瑚刺", "a coral spike fired at long range, sharp whistling projectile with a crunchy impact"),
	("p2eq_009", "月之刃·弧形刀光", "a crescent moon blade slash, bright ringing arcing slash with a silvery shimmer"),
	("p2eq_010", "激光长刃", "a laser blade arc slash, searing energy swoosh with an electric hum"),
	("p2eq_011", "饮血护符坠·连斩", "a flurry of blood-red slashes, rapid sharp cuts with a dark pulse"),
	("p2eq_012", "海藻·魔法护盾", "a magical seaweed barrier forming, soft watery shimmer"),
	("p2eq_013", "炙烤海胆·满层护盾", "spiky urchin armor hardening, crunchy spines locking with a shield hum"),
	("p2eq_014", "深海堡垒甲", "deep sea fortress armor hardening, heavy metallic plates clanking together"),
	("p2eq_015", "荆棘海胆·反伤护盾", "thorns reflecting damage, sharp spiny crack with a protective hum"),
	("p2eq_016", "铁壁盾·全队护盾", "an iron wall shield spreading to the team, heavy metallic clang with a protective hum"),
	("p2eq_017", "不沉之锚·击飞", "a heavy anchor slammed down, deep metallic clang with a chain rattle and a knock-up thud"),
	("p2eq_018", "守护贝壳·回血", "a guardian seashell healing, soft ocean shimmer with a warm chime"),
	("p2eq_019", "海葵药膏·治疗", "a sea anemone salve healing, gentle wet squish with a soft healing shimmer"),
	("p2eq_020", "哑铃·投掷", "a heavy dumbbell thrown and slamming, metallic whoosh into a heavy iron thud"),
	("p2eq_021", "守护贝母·连接", "a protective tether linking to an ally, soft resonant hum with a shell chime"),
	("p2eq_022", "余烬燃油瓶", "a fire bottle thrown and shattering, glass smash with a whooshing flame ignition"),
	("p2eq_023", "灼热火珊瑚·火焰波", "a wave of fire unleashed, roaring flame whoosh with crackling embers"),
	("p2eq_024", "龙蛋·喷火龙", "a small dragon summoned breathing fire across the field, roaring dragon flame rush"),
	("p2eq_025", "雷鸣贝壳·落雷", "a lightning bolt striking down from the sky, sharp thunder crack with a sizzling impact"),
	("p2eq_026", "雷电法杖·连锁闪电", "a chain lightning bolt jumping between targets, rapid crackling electric zaps"),
	("p2eq_027", "电棍·眩晕", "an electric baton strike, sharp electric zap with a stunning buzz"),
	("p2eq_028", "冰冻药剂", "a freezing vial shattering, glass break with an icy burst"),
	("p2eq_029", "冰封水母·冰道", "a frozen jellyfish pushing out a path of ice, crackling ice spreading with a cold whoosh"),
	("p2eq_030", "迷你水晶球A·光束", "a mini crystal ball firing a piercing beam, resonant crystal zap"),
	("p2eq_031", "迷你水晶球B·射线扫射", "a crystal ray sweeping across, resonant crystal beam with a shimmering sweep"),
	("p2eq_032", "唤灵骨符·骷髅", "an undead skeleton summoned, rattling bones rising with a dark magical whoosh"),
	("p2eq_033", "复活海螺·化虫", "a conch shell reviving its owner as a small bug, mystical conch resonance with a wet transformation"),
	("p2eq_034", "玩偶小熊·撞击", "a stuffed bear charging and bumping an enemy, soft heavy plush thump"),
	("p2eq_035", "黄铜齿轮·深海币", "a brass gear clicking and producing a coin, mechanical click with a bright coin clink"),
	("p2eq_036", "温泉蛋·孵化升级", "a hot spring egg hatching a level up, warm bubbling with a rising shimmer"),
	("p2eq_037", "蛋糕蜡烛·爆燃", "a cake candle flaring up, whooshing flame burst"),
	("p2eq_038", "信号放大器·电磁波", "an electromagnetic wave burst, rising electronic whine into a pulse blast"),
	("p2eq_039", "竹制弓箭·竹箭", "a bamboo arrow shot, bowstring twang with a wooden arrow thunk"),
	("p2eq_040", "FPGA板·古灵精怪枪", "a quirky gadget gun materializing, digital glitch with a mechanical click"),
	("p2eq_041", "退潮浊液·涨潮", "a rising tide surging, deep rushing water swell"),
	("p2eq_042", "涟漪药剂·全队回复", "a rippling healing wave spreading through the team, soft watery shimmer"),
	("p2eq_043", "海浪护符·浪墙", "a huge wave wall crashing across the battlefield, roaring ocean surge"),
	("p2eq_044", "深海项链·低血回复", "a deep sea necklace glowing to save its owner, deep resonant ocean hum with a healing swell"),
	("p2eq_045", "地狱护盾·低血回复与火球", "a hellfire shield bursting to life, roaring infernal flames with a healing surge"),
	("p2eq_046", "幽灵墨鱼·闪避护盾", "a ghostly squid ink shield after a dodge, wet ink puff with a spectral shimmer"),
	("p2eq_048", "黄铜手铳·连射", "a brass pistol firing several shots, crisp gunshots in quick succession"),
	("p2eq_049", "连发弩", "a repeating crossbow firing bolts, mechanical clack and bolt whoosh"),
	("p2eq_050", "幽灵加特林", "a ghostly gatling gun spinning up and firing a stream of bullets"),
	("p2eq_051", "激光手枪", "a laser pistol firing a piercing beam, sharp sci-fi zap"),
	("p2eq_052", "左轮手枪", "a revolver firing one heavy shot, loud gunshot with a ringing echo"),
	("p2eq_053", "霰弹贝古", "a shotgun blast of pellets, heavy boom with scattering pellets"),
	("p2eq_055", "病毒箭头·钩索炸弹", "a hook bomb thrown and latching on, metallic chain clink with a beeping fuse"),
	("p2eq_056", "飞镖", "darts thrown at marked targets, quick sharp whistles and thunks"),
	("p2eq_057", "狙击长管", "a sniper rifle firing, powerful gunshot crack with a long echoing tail"),
	("p2eq_058", "远古炮台·召唤", "an ancient turret deploying, heavy stone and metal mechanism locking into place"),
	("p2eq_059", "沙漏·时间停止", "time stopping, a deep reverse whoosh into a frozen ringing silence with a ticking clock"),
	("p2eq_060", "磷光水母伞·撑开", "a glowing jellyfish parasol opening, soft fabric whoosh with a bioluminescent shimmer"),
	("p2eq_062", "螳螂虾钳·重击", "a mantis shrimp claw punch, extremely fast snapping crack"),
	("p2eq_063", "白鲸气环·引爆", "air rings detonating, pressurized pop burst"),
	("p2eq_064", "溺者的浮囊·幽灵护盾", "a drowned ghost shield forming, eerie underwater bubbling with a spectral hum"),
	("p2eq_066", "鲸涎浓浆·饮药", "a thick potion gulped, liquid gulp with a powerful empowering swell"),
	("p2eq_067", "毒药瓶", "a poison vial thrown and shattering, glass break with a toxic hiss"),
	("p2eq_068", "深海气压罐·激光", "a pressure canister venting into a laser blast, hissing release with a beam zap"),
	("p2eq_069", "草莓蛋糕·回复", "eating a strawberry cake to heal, soft squishy bite with a sweet healing chime"),
	("p2eq_071", "炼乳罐·奶油护盾", "a creamy shield forming over the team, soft thick liquid swirl with a protective hum"),
	("p2eq_072", "铁皮蛋糕盒·化身礼盒", "a tin cake box transformation, metallic box clank with a festive shimmer"),
	("p2eq_073", "藤蔓弓弦·藤蔓箭", "a vine arrow shot, organic whip twang with a leafy whoosh"),
	("p2eq_075", "银色箭袋·箭雨", "a rain of silver arrows falling, many arrows whistling down and thudding"),
	("p2eq_076", "连发弩机·竹箭连射", "rapid bamboo bolts fired, quick crossbow clacks with piercing whooshes"),
	("p2eq_078", "电鳗双管铳", "an electric eel double-barrel shotgun, shotgun blast with an electric crackle"),
	("p2eq_079", "珊瑚急救塔·治疗", "a coral healing turret firing a healing pulse, soft watery zap with a healing shimmer"),
	("p2eq_080", "打捞旋翼机·地毯轰炸", "a salvage helicopter carpet bombing, rotor whir with a series of explosions"),
	("p2eq_081", "藤编圆盾·举盾", "a woven rattan shield raised, sturdy creaking wood with a protective thump"),
	("p2eq_082", "护心甲·回复", "a heart guard armor pulsing, metallic thump with a heartbeat healing pulse"),
	("p2eq_084", "手半剑·十字斩", "a cross slash with a hand-and-a-half sword, two crossing heavy steel slashes"),
	("p2eq_086", "六分仪浮游炮·终极射线", "floating drones firing an ultimate converging ray, rising charge into a massive beam blast"),
	("p2eq_087", "盗令潜水钟·偷取技能", "a diving bell stealing a spell, deep underwater bell clang with a magical swirl"),
	("p2eq_088", "涨潮碑", "a tidal monolith rising from the ground, heavy stone grind with rushing water"),
	("p2eq_089", "蚀月符纸", "an eclipse talisman slapped onto an enemy, paper slap with a dark magical burn"),
	("p2eq_090", "镇海杵·跃起猛砸", "a heavy sea pestle slam after a leap, massive ground pound with a deep shockwave"),
	("p2eq_091", "远古龟甲片·回复", "an ancient turtle scute glowing, soft stony resonance with a healing chime"),
	("p2eq_092", "毒蛾茧·毒蛾", "a poisonous moth released, fluttering wings with a toxic mist hiss"),
	("p2eq_093", "香火石·强化", "an incense stone empowering attacks, smoky whoosh with a temple bell ring"),
	("p2eq_094", "祖龟碑·立碑与石雷", "an ancestral turtle monument rising, heavy stone grind with a thunderous rock strike"),
	("p2eq_096", "小木斧·斧头", "a small wooden axe chopping, sharp wooden chop with a satisfying thunk"),
]

# ── 全局: 小将 / 召唤物的通用命中、护盾、治疗、阵亡、开战、胜负、界面 ─────────────────────────────
G = [
	("g_hit", "通用命中(小将 / 召唤物 / 没有专属声的)", 0.5, 4, "TFT minion BasicAttack_OnHit", "a solid weapon impact on a body, punchy mid thump with a short crunchy transient"),
	("g_crit", "通用暴击", 0.7, 3, "LoL CritAttack_OnHit", "a critical strike, heavy crunchy impact with a bright crack and a deep bass punch"),
	("g_skill_hit", "技能命中(没有专属命中的技能)", 0.6, 3, "LoL spell hit", "a magical ability impact on an enemy, punchy energy burst with a solid thump"),
	("g_shield_gain", "得盾", 1.0, 3, "TFT shield", "a protective magical shield forming, quick rising resonant shimmer with a solid hum, bright and clean"),
	("g_shield_break", "盾破", 0.8, 3, "TFT shield break", "a magical shield shattering, glassy energy crack with a short dissipating shimmer"),
	("g_heal", "治疗", 1.0, 3, "TFT heal", "a soft magical heal, warm rising shimmer with a gentle chime"),
	("g_death", "单位阵亡", 1.2, 3, "TFT unit death", "a champion defeated, a heavy body collapse thud with a dissipating magical whoosh"),
	("g_rebirth", "复活", 1.8, 2, "Anivia/Zilean revive", "a heroic resurrection, rising radiant swell with a powerful magical burst"),
	("g_dodge", "闪避", 0.5, 3, "TFT dodge", "a quick dodge, fast airy whoosh"),
	("fight_start", "开战", 2.2, 3, "TFT combat start", "the start of a battle, a powerful war horn and a huge cinematic drum impact"),
	("victory", "胜利", 3.0, 3, "TFT victory", "a triumphant short orchestral victory sting with brass and a big cymbal swell"),
	("defeat", "失败", 3.0, 3, "TFT defeat", "a somber short orchestral defeat sting, low strings and a fading drum"),
	("ui_click", "按钮点击", 0.5, 3, "LoL client click", "a crisp polished user interface click, short and clean, subtle metallic tick"),
	("ui_confirm", "确认 / 开始", 0.5, 3, "LoL client confirm", "a polished user interface confirm, bright clean magical tick with a short shimmer"),
	("ui_back", "返回 / 关闭", 0.5, 3, "LoL client back", "a polished user interface back click, soft short low tick"),
	("reward_normal", "普通奖励", 1.2, 3, "TFT orb pickup", "a reward collected, bright magical sparkle with a satisfying chime"),
	("reward_rare", "稀有奖励", 1.8, 3, "TFT legendary orb", "a rare legendary reward revealed, magical burst with shimmering bells and a deep swell"),
	("level_up", "升级", 1.6, 3, "TFT level up", "a level up, rising magical swell ending in a bright resonant chime"),
	("coin_buy", "金币购买", 0.6, 3, "TFT buy", "a satisfying gold purchase, a few gold coins clinking with a crisp clean ring"),
	("match_found", "匹配成功", 1.6, 3, "LoL match found", "a match found alert, an energetic magical sting with a bright swell"),
	("studio_intro", "工作室开场(灯鱼点灯)", 2.5, 3, "Riot logo sting", "a polished studio logo sting: two tiny bright sparks, then a warm magical lantern igniting with a soft whoosh and a glowing swell, ending in a gentle shimmering chime"),
]


def build() -> dict:
	items = []
	for tid, t in T.items():
		kind = "melee" if tid in MELEE else "ranged"
		items.append({"key": "bas_" + tid, "zh": t["zh"] + "·普攻出手", "cat": "ba_cast", "dur": 0.6, "n": 3,
			"ref": t["ref"] + " BasicAttack_OnCast", "text": "%s basic attack %s: %s, made of %s. One short snappy sound." % (
				kind, "swing" if kind == "melee" else "launch", t["bas"], t["mat"])})
		items.append({"key": "bah_" + tid, "zh": t["zh"] + "·普攻命中", "cat": "ba_hit", "dur": 0.6, "n": 4,
			"ref": t["ref"] + " BasicAttack_OnHit", "text": "basic attack impact: %s. Tight punchy transient, solid low-mid body, quick tail." % t["bah"]})
		items.append({"key": "crit_" + tid, "zh": t["zh"] + "·暴击", "cat": "crit", "dur": 0.8, "n": 2,
			"ref": t["ref"] + " CritAttack_OnHit", "text": "critical strike impact: %s. Heavier and bigger than a normal hit, deep bass punch." % t["crit"]})
	for stype, zh, dur, ref, cast, hit in S:
		items.append({"key": "sk_" + stype, "zh": zh + "·放出", "cat": "sk_cast", "dur": dur, "n": 3, "ref": ref + " OnCast",
			"text": "ability cast: %s. Clear wind-up, strong release and a short natural tail." % cast})
		if hit:
			items.append({"key": "skh_" + stype, "zh": zh + "·命中", "cat": "sk_hit", "dur": 1.2, "n": 3, "ref": ref + " hit",
				"text": "ability impact: %s." % hit})
	for iid, zh, text in E:
		items.append({"key": "eq_" + iid[5:], "zh": zh, "cat": "equip", "dur": 1.0, "n": 2, "ref": "TFT item proc",
			"text": "item effect: %s. Distinct and satisfying, short natural tail." % text})
	for key, zh, dur, n, ref, text in G:
		items.append({"key": key, "zh": zh, "cat": "global", "dur": dur, "n": n, "ref": ref, "text": text + "."})
	return {"_doc": "音效 v2 描述表(tools/assetgen/sfx_v2_table.py 生成, 勿手改)。2026-11-05 全部重做, 对标云顶 / LoL。v2r2 = 第二轮(见 round2 头注)。",
		"style": STYLE, "styles": {"v2r2": STYLE_R2, "v2r3": STYLE_R3, "v2sw": STYLE_SW},
		"batches": {"v2": items, "v2r2": round2(items), "v2r3": round3(items), "v2sw": sweeteners()}}


## ── 低频垫底层(v2sw): 不是事件, 是给「技能放出」垫分量用的素材 ──────────────────────────────────────
## 三轮选中的技能放出低频占比 0.12(Riot 0.41)、质心 2152 Hz(1141) ⇒ 偏薄。直接让生成器出「有分量」的放出会出一团轰鸣(第一轮 35 条全否)。
## 商业做法: 主体声 + 一层低频「甜味剂」(sweetener)。build_sfx_v2 给低频不够的放出声在起音处垫一层(低通 220 Hz)。
STYLE_SW = "High-fidelity cinematic game sound design layer, clean, no music, no speech"
SW = [
	("sw_boom", "a deep cinematic impact boom with a sub-bass thump, short and clean"),
	("sw_swell", "a deep magical energy whoosh swell with heavy low end"),
	("sw_earth", "a deep earthy rumble impact, short"),
	("sw_body", "a low heavy body hit thud with weight"),
	("sw_fire", "a deep fiery whump burst with heavy low end"),
	("sw_pulse", "a deep resonant magical pulse boom"),
]


def sweeteners() -> list:
	return [{"key": k, "zh": "低频垫底层", "cat": "sweetener", "dur": 1.2, "n": 4, "ref": "-", "text": t + "."} for k, t in SW]


## ── 第三轮(v2r3): 两轮 6~7 个候选全被否决的 7 条(都是「只剩低频轰鸣」或「像素感」), 每条 4 个候选, 描述逐条重写成「清脆、有细节」 ──
STYLE_R3 = "High-fidelity fantasy MOBA game sound effect in the style of League of Legends, professionally layered, crisp, no music, no speech"
R3 = {
	"crit_angel": "critical strike impact: a searing holy smite, bright crackling radiant burst with ringing celestial bells and a sharp crack. Crisp, bright, high detail, short.",
	"crit_phoenix": "critical strike impact: a blazing fireball explosion, sharp crackling flame burst with sizzling embers and a bright snap. Crisp, bright, high detail, short.",
	"sk_rockShockwave": "ability cast: a stone giant stomps, sharp rock cracking and splitting, gravel and pebbles scattering outward with crunchy detail and a solid impact. Crisp and detailed, not a low rumble.",
	"sk_stoneTaunt": "ability cast: a heavy war drum hit followed by a sharp stone slam, rocks cracking and debris clattering with crunchy detail. Crisp and detailed, not a low rumble.",
	"eq_038": "item effect: an electromagnetic pulse burst, crackling electric discharge with a sharp zap and buzzing static sweep. Realistic, crisp, detailed.",
	"eq_080": "item effect: a helicopter rotor whirring overhead and a quick series of bomb explosions with debris. Realistic, crisp, detailed.",
	"eq_082": "item effect: a metal armor plate thump with a soft glowing heartbeat pulse and a bright healing chime. Crisp, bright, detailed.",
}


def round3(items: list) -> list:
	by = {it["key"]: it for it in items}
	out = []
	for k, t in R3.items():
		it = dict(by[k])
		it["text"] = t
		it["n"] = 4
		it["dur"] = max(0.8, min(1.6, it["dur"]))
		out.append(it)
	return out


## ── 第二轮(v2r2) ──────────────────────────────────────────────────────────────────────────
## 第一轮量出来(tools/sfx_pick_v2.py 报告, 选中的中位 vs Riot 同类中位):
##   普攻命中 低频占比 0.66(Riot 0.35)、质心 877 Hz(2220) · 暴击 0.83 / 524 Hz(0.33 / 2220) ⇒ 太闷: 我写的「deep bass」「sub-bass」
##   让生成器出了一团低频; 35 条事件三个候选全是质心 < 180 Hz 的轰鸣(手机喇叭放不出) ⇒ 一个都不能用。
##   技能放出 低频 0.12(Riot 0.41)、质心 2306(1129) ⇒ 太薄。技能命中 / 装备比 Riot 短 0.3~0.5 秒。
## 第二轮: 风格换成「清脆瞬态 + 中高频细节 + 不发闷」; 命中 / 暴击去掉低频字眼、写明「明亮的碎裂瞬态」; 技能放出写明「有分量」;
##   命中 / 装备加长。两轮候选合在一起挑(sfx_pick_v2 读 v2 与 v2r2 两个目录)。
STYLE_R2 = ("High-fidelity fantasy MOBA game sound effect in the style of League of Legends and Teamfight Tactics, professionally layered, "
	"crisp punchy transient, balanced full frequency range with clear mid and high detail, not muddy, not just a low rumble, no music, no speech")
_DEBASS = [("earth-shaking ", "powerful "), ("sub-bass ", ""), ("deep bass punch", "solid punch"), (" deep ", " "), ("deep ", ""),
	(" and a bass thump", " and a solid thump"), ("bass ", "")]
DUR_R2 = {"ba_cast": 0.7, "ba_hit": 0.7, "crit": 0.9, "sk_hit": 1.4, "equip": 1.3}


def _debass(t: str) -> str:
	for a, b in _DEBASS:
		t = t.replace(a, b)
	return t


def round2(items: list) -> list:
	out = []
	for it in items:
		r = dict(it)
		cat = it["cat"]
		t = it["text"]
		if cat == "ba_hit":
			t = _debass(t.replace(" Tight punchy transient, solid low-mid body, quick tail.", "")) + \
				" Crisp crunchy transient with bright detail and a solid mid punch, short tail, not muddy."
		elif cat == "crit":
			t = _debass(t.replace(" Heavier and bigger than a normal hit, deep bass punch.", "")) + \
				" Bigger than a normal hit: sharp bright crack, crunchy layered impact, short punch, not muddy."
		elif cat == "sk_cast":
			t = t + " Full-bodied with real weight, but bright and detailed, not just a rumble."
		elif cat in ("sk_hit", "equip"):
			t = _debass(t) + " Crisp and bright with a satisfying tail."
		elif cat == "ba_cast":
			t = _debass(t) + " Crisp and airy."
		r["text"] = t
		r["dur"] = DUR_R2.get(cat, it["dur"])
		out.append(r)
	return out


if __name__ == "__main__":
	d = build()
	open(OUT, "w", encoding="utf-8", newline="\n").write(json.dumps(d, ensure_ascii=False, indent=1) + "\n")
	from collections import Counter
	for bn, its in d["batches"].items():
		c = Counter(it["cat"] for it in its)
		gens = sum(it["n"] for it in its)
		secs = sum(it["n"] * it["dur"] for it in its)
		print("%s: 事件 %d 条 %s · 候选 %d 个 · 合计 %.0f 秒" % (bn, len(its), dict(c), gens, secs))
