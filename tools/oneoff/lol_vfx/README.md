# LoL 特效配方拆解（只读，学习用）

2026-11-14 拆娜美大招用。Riot 的素材只当尺子：**不进仓库、不进游戏**，解出来的东西放 scratchpad 或 `.out/`。

| 脚本 | 做什么 |
|---|---|
| `wad_extract.py <wad> <输出目录> [路径… / --scan]` | 读本机 `D:/Riot Games/League of Legends/Game/DATA/FINAL/Champions/<英雄>.wad.client`(v3)，按 xxh64(小写路径) 找条目、zstd 解压。`--scan` 存所有含 `Nami_Base_R` 的 PROP bin（改脚本里的字样换英雄） |
| `binparse.py <bin 目录> <输出 json>` | 解析 PROP .bin，找 `Characters/<英雄>/Skins/Skin0/Particles/<系统名>` 的 VfxSystemDefinitionData（发射器、贴图、寿命、速度、颜色、混合、模型） |
| `scb.py <scb…>` | 解析静态网格 .scb，打印顶点 / 面数 / 尺寸 / 材质名，画俯视 + 侧视线框 `meshes.png` |

要点：新版本里粒子定义不在 `skin0.bin`，在哈希命名的 `*_Multi_Skins_*.bin` 里，CommunityDragon 上没有，只能从本机资源包解。贴图 png 可从 `raw.communitydragon.org/latest/game/assets/...` 下载。依赖：`xxhash`、`zstandard`、`Pillow`。
