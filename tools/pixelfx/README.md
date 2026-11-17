# pixelfx 接入管线

把 [pixelfx](https://github.com/patch-gg/pixelfx) 的 244 个像素特效烘焙成本项目的序列帧表，
再由编辑器面板「特效工坊」挑选 / 换色 / 烘焙 / 绑定。**游戏仓库里不放任何 JS 源码**，只放烘焙产物。

## 一次性准备

```bash
# 1) 库放到游戏仓库之外（默认路径，可用 --lib 或环境变量 PIXELFX_HOME 改）
git clone --depth 1 https://github.com/patch-gg/pixelfx.git E:/skill/game/pixelfx

# 2) 导出特效目录表（面板读它，不读 JS）
node tools/pixelfx/dump_meta.mjs        # -> assets/fx/pixelfx/catalog.json

# 3) 导出项目内容树（BOSS → 招式 → 当前 motif / 五行）
godot --headless --path . tools/dump_content_map.tscn -- --no-save   # -> content_map.json
```

第 3 步为什么要有：面板是编辑器 `@tool` 脚本，**不能**直接调 `SkillDB / MoveDB / ArtDB`
（那些脚本不是 @tool），所以让项目自己跑一遍把树拍成 JSON 给面板读。
新增 BOSS / 改招式表之后重跑第 3 步即可。

需要 Node ≥ 18。烘焙/GIF 之外没有依赖（`esbuild` 只有库自己做网页画廊时才要）。

## 日常烘焙

```bash
node tools/pixelfx/bake.mjs ice/frost-nova                       # 用特效自带色带
node tools/pixelfx/bake.mjs ice/frost-nova --palette fire        # 换成库内 27 条色带之一
node tools/pixelfx/bake.mjs fire/torch --palette "#102,#215,#43a,#8cf,#cff,#fff" --variant bluefire
node tools/pixelfx/bake.mjs fire/torch --set reach=120 --seed 7 --fps 24
node tools/pixelfx/bake.mjs melee --all-in-category              # 整类
node tools/pixelfx/bake.mjs --jobs tools/pixelfx/bake_jobs.json  # 批量（编辑器面板就是这么调的）
```

产物：`assets/fx/pixelfx/<类>/<特效>__<变体>.png` + 同名 `.json`（Aseprite 格式，
`meta.pixelfx` 里带 `frames / fps / loop / frameSize / pivot / columns / act 命中时序`）。

每次成功打印一行机器可读的回执：

```
BAKE_OK <id> <variant> <res路径> <帧数> <fps> <宽> <高> <列数> <pivotX> <pivotY> <loop|once>
```

## 两种烘焙：先看，再决定要不要进游戏

| 按钮 | 产物落点 | 会被 Godot 导入吗 | 能绑定 / 挂场景吗 |
|---|---|---|---|
| **烘焙预览（不进游戏）** | `user://pixelfx_preview/<类>/<名>__<变体>.png|json` | **不会**（绝对路径裸读，`Image.load_from_file`） | 不能 —— 游戏运行时读不到 user:// 缓存 |
| **烘焙并导入** | `res://assets/fx/pixelfx/…` | 会（reimport + scan） | 能 |

预览区在项目之外：不进 git、不会被打进导出包、不占素材体积；面板的预览台照常实时播。
列表标记三态：`●` 已导入游戏、`◐` 只有预览版、`○` 还没烘。「清空预览缓存」只删 `user://` 那一坨。

命令行也能只烘来看：

```bash
node tools/pixelfx/bake.mjs water/fountain --out "$APPDATA/Godot/app_userdata/万界秘境/pixelfx_preview"
```

回执此时报的是**绝对路径**而不是 `res://`，面板据此跳过 reimport。

## 编辑器面板「特效工坊」

插件在 [addons/pixelfx_studio](../../addons/pixelfx_studio)，已在 `project.godot` 里启用。
Godot 底部面板 → **特效工坊**。左栏两种模式：

- **按 BOSS / 招式**（默认）：选 BOSS → 选它的一门招式 → 左栏自动换成**这一招的候选特效**
  （按该招的五行属性 + 当前演出 motif 命中关键词排序，一次性特效优先；`●` 已烘焙）。
  面包屑「剑客功法 › 刺 › 候选 81 个」+「← 招式」返回。
- **按特效分类**：直接翻 21 个特效大类（已给中文名：法术 / 近战 / 受击 / 投射物 / 连招 / 状态 …），
  可搜索名字、描述、标签。

三种模式共用的右栏与底部：

1. **选形态**：从左边列表挑特效，`●` 是已烘焙、`○` 还没烘。
2. **选颜色**：右上 12 个快捷按钮（金木水火土风雷冰毒圣暗血）直接套库内色带；
   下面 27 条色带各自带渐变小图可以 eyeball 比冷暖；再下面能粘自己的 hex 列表。
   **改色必须重烘**（产物不是索引色），所以选完要按「烘焙并导入」。
3. **调大小 / 朝向**：缩放滑条、翻转、加法混合、`半径 200px` 一键把特效半宽对齐判定半径。

底部四个动作：

| 按钮 | 做什么 |
|---|---|
| 烘焙并导入 | 同步调 `node bake.mjs --jobs …`，产物落 `assets/fx/pixelfx/`，然后 reimport + 刷新预览 |
| 挂到选中节点 | 给场景里选中的 `Node2D` 加一个 `PixelFxFx` 子节点（可撤销，`Ctrl+S` 保存场景） |
| 绑定到这一招 | 把「当前特效 + 变体 + 大小 + 加法混合」写进 `assets/fx/pixelfx/bindings.json`，进游戏放这招就是像素版 |
| 解除绑定 | 从绑定表删掉这一招，立刻回到原来的云烟演出 |
| 打开输出目录 | 直接看烘焙出来的 PNG/JSON |

设置项在 项目设置 → 编辑器 → `pixelfx_studio`：`library_path` / `node_path` / `output_dir`。

## 招式怎么切到像素通道

`SkillFx` 里多了一个 motif 分支，**现有招式一条都没动**。绑定有两处来源，优先级从高到低：

1. `assets/fx/pixelfx/bindings.json` —— 面板「绑定到这一招」直接读写的表，不碰源码：

```json
{
	"skill_sword_stab": {
		"pixelfx": "melee/sword-slash", "pixelfx_variant": "default",
		"pixelfx_scale": 1.0, "pixelfx_additive": false,
		"pixelfx_flip_by_dir": true, "note": "刺"
	}
}
```

2. `ArtDB.SKILL_FX` 条目里手写的同名键（想把它固化进代码时用）：

```gdscript
"skill_xxx": {"motif": "pixel", "pixelfx": "ice/frost-nova", "pixelfx_variant": "ice",
    "pixelfx_scale": 1.0, "pixelfx_additive": false,
    "pixelfx_flip_by_dir": true, "pixelfx_fit_radius": false},
```

- 没写 `pixelfx` 键、或那张表还没烘出来 → 自动退回原来的云烟演出，不会放出空招。
- 震屏、命中停顿、挥武器仍由 `SkillFx` 负责，像素表只替换「画出来的那一层」。
- 表里的 `act.hits` 会随帧发出 `hit_fired` 信号，`first_hit_time()` 给出第一下命中的秒数，
  用来对齐出伤（本项目要求出伤同帧）。


## 要点

- **244 个特效全部有中文名**：`assets/fx/pixelfx/effects_cn_map.json`（`id → {name, desc}`），
  按库里每条自己的 `desc` 逐个手写，不是机翻原名。面板列表、信息行、搜索都吃这张表；
  没登记的 id 自动退回英文原名。**改这张表不需要重跑 dump_meta**（catalog 会被它覆盖，cn_map 不会）。
  库里新增特效后，`node tools/pixelfx/dump_meta.mjs` 再给新 id 补一条中文名即可。
- **默认不含灰色小人**：特效的 `meta.actor` 只是取景用的替身，烘焙时 `renderFrames` 的 `actor:false`
  只导出纯特效层（透明）。要在预览里看带角色的演出，面板勾上「含角色」。
- **换色必须重新烘焙**：产物不是索引色（单帧有上万个 RGBA 值，软边和光晕用了 alpha），
  所以运行时 shader 换色做不到。一次烘焙 1~3 秒，编辑器面板把「改色 → 重烘 → 重导入」串成一个按钮。
- 库更新后重跑 `dump_meta.mjs`，目录表会跟着更新；已烘焙的表不受影响。
- 许可与归属见 [docs/NOTICE_pixelfx.md](../../docs/NOTICE_pixelfx.md)。
