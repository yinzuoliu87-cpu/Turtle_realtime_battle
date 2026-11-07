"""把剩余过渡写成任务清单 .out/review/queue.json"""
import json
import sys

sys.stdout.reconfigure(encoding="utf-8")
R = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/.out/review/"
refs = {}
for line in open(R + "refs.txt", encoding="utf-8"):
    t, n, r = line.split()
    refs[(t, n)] = r
BASE = {"cyber": "upload:9e491a95-a55b-4251-a359-706d8e2559ac", "crystal": "upload:fca9c045-15a3-4f1d-b1a8-f199e3e55505", "chest": "upload:d148b61b-191e-49f7-a20f-a58623f90560",
        "space": "upload:14dca3fe-3fad-4a5f-8e42-6cef14ea0e5c", "hiding": "upload:e0805054-1614-4c40-911f-2b9e92b8e7b8", "headless": "upload:2bca59cd-20aa-4908-95d5-6ec1ef3b138d",
        "bubble": "upload:d6a792b5-72ef-49c8-b435-a0cd7544fb92"}
SUB = {"cyber": ("a cyborg turtle in grey armor with a cyan visor and a mechanical backpack holding a laser rifle", "standing in a firm stance holding the rifle low", "Keep exactly two arms and one rifle."),
       "crystal": ("a purple stone turtle knight with crystal spires on its shell, a crystal spear and one round buckler", "standing tall holding the spear upright", "Keep exactly two arms, one spear and one buckler."),
       "chest": ("a stocky olive turtle with a gold tooth and a treasure chest strapped to its back", "standing with bow legs rubbing its hands together", "Keep exactly two arms and one chest."),
       "space": ("a small astronaut turtle with a glass helmet, a white suit, a galaxy shell and a star staff", "floating lightly holding the star staff up", "Keep exactly two arms and one staff."),
       "hiding": ("a timid turtle with an enormous round brown shell, a small head and stubby limbs", "standing nervously with hands at its chin", "Keep exactly two arms."),
       "headless": ("a headless grey undead turtle with a bone shell, purple smoke from the neck stump and a mouth on its belly", "standing hunched and menacing", "Keep exactly two clawed arms and no head."),
       "bubble": ("a chubby round aqua turtle with a soap bubble shell holding a long bubble wand", "standing holding the wand upright", "Keep exactly two arms and one wand.")}
## 龟: 段前缀 -> (姿势, 进入描述, 收回描述)
ACT = {
    "cyber": {},
    "crystal": {"a": ("hit", "the knight draws the spear back along its side, then thrusts it forward in a long powerful lunge", "the knight pulls the spear back and stands tall again"),
                "s": ("wall", "the knight sets the spear on the ground, crouches low and shoves the round buckler forward like a wall", "the knight lowers the buckler, lifts the spear and stands tall again"),
                "f": ("burst", "the knight lifts the spear high with the tip down and stabs it hard into the ground in front of it", "the knight pulls the spear out of the ground and stands tall again"),
                "d": ("ball", "the knight lifts the spear high overhead and a violet crystal orb gathers above the tip", "the orb floats away, the knight lowers the spear and stands tall again")},
    "chest": {"a": ("hit", "the turtle swings the heavy chest off its back and up over its shoulder, then slams it down on the ground in front of it", "the turtle heaves the chest back up onto its back and straightens up"),
              "s": ("count", "the turtle sits down on the ground, opens a pouch and holds up a gold coin close to its face, grinning", "the turtle tucks the coins away and stands back up"),
              "f": ("storm", "the turtle lifts the chest off its back, raises it high overhead with both arms and throws the lid open, coins fountaining up", "the coins stop, the turtle lowers the chest onto its back and straightens up"),
              "d": ("cannon", "the turtle swings the chest to its hip, points it forward, the lid opens and a gold coin blasts out", "the turtle swings the chest back onto its back and straightens up")},
    "space": {"a": ("hit", "the astronaut draws the staff back, then leans forward and points it straight ahead as a burst of light fires from the star", "the astronaut drifts back upright and lifts the staff again"),
              "s": ("worm", "the astronaut grips the staff in both hands, curls up and strains as a small dark wormhole swirls open in front of the star", "the wormhole closes, the astronaut uncurls and floats upright again"),
              "f": ("wave", "the astronaut curls up tight, then flings both arms wide open arching its back, the galaxy shell glowing", "the astronaut relaxes its arms and floats upright again"),
              "d": ("warp", "the astronaut raises the staff slowly with both hands straight above its helmet, the star turning purple", "the astronaut lowers the staff and floats upright again")},
    "hiding": {"a": ("hit", "the turtle pulls its head in nervously, then the neck shoots far out to the left and the head snaps forward in a quick bite", "the neck pulls back in and the head returns to the front of the shell"),
               "s": ("shrink", "the turtle gasps and pulls its head, arms and legs quickly inside the shell until only two small eyes peek from the dark opening", "the legs, arms and head slowly come back out of the shell"),
               "f": ("defend", "the turtle spins around so the huge shell faces forward like a wall, crouching behind it", "the turtle turns back around to face forward"),
               "d": ("buff", "the head stretches up tall out of the shell and both stubby arms are thrown up in the air, shouting a cheer", "the arms come down and the head sinks back to normal")},
    "headless": {"a": ("hit", "the monster rears back, then throws its whole body forward, the belly mouth stretching wide open to bite, both claws reaching", "the monster pulls back and hunches again, the belly mouth closing"),
                 "s": ("fear", "the monster hunches down, then rears up tall, flinging both arms wide, the belly mouth screaming and purple smoke bursting from the neck", "the smoke shrinks, the arms come down and the monster hunches again"),
                 "f": ("tendril", "the monster shudders and many long dark purple tendrils burst out of the neck stump and the cracks of its shell, spreading in all directions", "the tendrils pull back into the body and the monster straightens"),
                 "d": ("soul", "the monster steps forward and raises one long clawed arm high, purple flame gathering around the claws", "the flame fades, the arm comes down and the monster hunches again")},
}
Q = []


def add(t, seg, first, last, frames, desc):
    s = SUB[t]
    Q.append(dict(t=t, seg=seg, first=first, last=last, frames=frames, desc=desc + " " + s[2], subject=s[0], pose=s[1]))


## 赛博龟只差 4 段
add("cyber", "d_out", refs[("cyber", "ai")], BASE["cyber"], 4, "the glow settles, the gunner lowers the rifle and returns to its firm stance.")
add("cyber", "k_in", BASE["cyber"], refs[("cyber", "dead")], 8, "the machine takes a final blow: it sparks, its knees give way and it collapses flat on its belly with the rifle falling beside it. It does not jump.")
add("cyber", "idle", BASE["cyber"], BASE["cyber"], 8, "subtle idle loop: the shoulders rise and fall very slightly, the visor glow pulses, both feet stay planted and do not move.")
add("cyber", "walk", BASE["cyber"], BASE["cyber"], 8, "one full steady armored march in place: one leg steps forward then the other, the feet lift off the ground in turn, the rifle stays in both hands.")
DEATH = {"crystal": "the knight takes a final blow, staggers, drops the spear and the buckler and topples forward flat on its belly, staying down. It does not jump.",
         "chest": "the turtle takes a final blow, staggers under the weight of the chest and is crushed flat on its belly as coins spill out. It does not jump.",
         "space": "the astronaut takes a final blow, the helmet cracks, it drifts backward and falls flat on its back, the staff dropping beside it. It does not jump.",
         "hiding": "the turtle takes a final blow, wobbles, tips over and rolls onto its back on the round shell with its limbs sticking up. It does not jump.",
         "headless": "the monster takes a final blow, staggers, its legs give way and it collapses in a heap as the smoke fades. It does not jump."}
IDLE = {"crystal": "subtle idle loop: the chest rises and falls very slightly, the crystals glint, both feet stay planted and do not move.",
        "chest": "subtle idle loop: the shoulders rise and fall very slightly, the hands rub together a little, both feet stay planted and do not move.",
        "space": "subtle idle loop: the astronaut bobs up and down a tiny bit as if floating, the star twinkles, the body otherwise stays in place.",
        "hiding": "subtle idle loop: the small head trembles nervously a tiny bit and the eyes dart, both feet stay planted and do not move.",
        "headless": "subtle idle loop: the shoulders heave very slightly, the purple smoke sways, the belly mouth breathes, both feet stay planted and do not move."}
WALK = {"crystal": "one full heavy march in place: one leg steps forward then the other, the feet lift off the ground in turn, the spear stays upright.",
        "chest": "one full waddling walk in place with bow legs: one leg steps forward then the other, the feet lift off the ground in turn, the chest bounces on its back.",
        "space": "one full slow moon walk in place: the legs swing one after the other in the air, the body floats and bobs gently.",
        "hiding": "one full slow shuffle in place: the two stubby legs step one after the other, the feet lift off the ground in turn, the huge shell rocks side to side.",
        "headless": "one full lurching zombie walk in place: one leg drags forward then the other, the feet lift off the ground in turn, the arms hang and swing."}
for t in ("crystal", "chest", "space", "hiding", "headless"):
    for pre, (key, a, b) in ACT[t].items():
        add(t, pre + "_in", BASE[t], refs[(t, key)], 8, a + ".")
        add(t, pre + "_out", refs[(t, key)], BASE[t], 4, b + ".")
    add(t, "k_in", BASE[t], refs[(t, "dead")], 8, DEATH[t])
    add(t, "idle", BASE[t], BASE[t], 8, IDLE[t])
    add(t, "walk", BASE[t], BASE[t], 8, WALK[t])
add("bubble", "h_in", BASE["bubble"], refs[("bubble", "shield")], 8, "the turtle swings the wand in a big circle above its head and a huge glossy bubble grows in the air in front of it. Feet stay planted.")
add("bubble", "h_out", refs[("bubble", "shield")], BASE["bubble"], 4, "the big bubble floats away out of the left side and the turtle lowers the wand to its side. Feet stay planted.")
add("bubble", "n_in", BASE["bubble"], refs[("bubble", "bind")], 8, "the turtle takes a breath, grips the wand in both hands and thrusts it forward, a stream of small bubbles and a sticky ribbon of foam shooting out. Feet stay planted.")
add("bubble", "n_out", refs[("bubble", "bind")], BASE["bubble"], 4, "the foam ribbon breaks away to the left and the turtle lowers the wand to its side. Feet stay planted.")
json.dump(Q, open(R + "queue.json", "w", encoding="utf-8"), ensure_ascii=False, indent=0)
print("任务数", len(Q))
print(Q[5])
