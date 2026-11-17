# BOSS 美术管线：序列帧 / 骨骼 / 抠幕

> 从 `.workbuddy/memory/MEMORY.md` 抽出的操作手册（2026-11-09）。
> 只讲「怎么做 + 哪里会错」，不记某个 BOSS 的当前状态。工具脚本都在 `tools/`。

- 管线 `tools/gen_boss_sprite_frames.py`（split/preview/compose），中间产物 `vibe_images/boss_work/manifest.json`。compose 每帧钳进本格 + 丢弃 < 最大连通块 1.5% 的碎片。招式动作名登记 `ArtDB.BOSS_MOVE_ANIMS`（未登记 = 出招没动作）；换大体型同步放大碰撞圆。
- 移动动画 = 骨骼（`ArtDB.VISUALS.<id>.rig` → `BossRig` + `BossRigData` + `tools/build_*_rig.py`），🚫 序列帧做不出丝滑移动。人形不拆头；分件补画被遮躯干；刀多边形上缘在下缘之上。
- ⚠ 坐标口径：`part_joint` = 关节相对 rig 原点（画布中心）；`part_offset` = 贴图中心 − 自身关节（整画布分件恒 = −joint）；`muzzle_offset` = 出手点相对部件关节，取**手部**不是武器顶端。⚠ 招式判定帧 = `windup × length/(windup+0.15)`，不是 windup；一次性动作收尾以 `BossRig.one_shot_finished()` 为准。⚠ 验证必须从 `boss._begin_attack(kind)` 起，不能直接调 `_play_form_anim`。
- 动画轨道：⚠ 旋转必须 LINEAR（CUBIC 过冲 50%）；⚠ 节点属性被任一动画写过，所有循环动画都补归零轨道 `_neutral_all()`；`AnimationPlayer` track 必须写 `body/head:rotation`（扁平路径静默失效）。曲线「慢蓄力 → 蓄满定住 → 极速爆发 → 打击定格（两相邻同值帧）→ 缓回收」。赛璐璐化只能重画（`boss_art_prompts.py` 的 `STYLE_CEL`，🚫 别改全局 `STYLE`）。2D 刚体分块白缝：圆盘内填最近色 + body 挖洞高斯 sigma=4 + 摆角控在洞不可见区；别用 `binary_fill_holes` 量关节洞。
- ⚠ ImageGen 出 opaque 地面图右下角带「AI生成」水印，平铺会重复 36 次 → 导出前裁 16:9 上半部避开。⚠ 传 `transparent` 出来其实是 RGB、棋盘格画进像素：按「平坦浅无彩色」判据（`min≥205` + `max-min≤10` + 3×3 局部 std<6）取连通块清掉，导出时**底边贴齐画布下沿**（`anchor_bottom` 才准）。
- ⚠ 抠幕键色必须实测（四角 32×32 中位色），判据用洋红度 `mag = min(r,b) − g` 软阈值（🚫 到 KEY 的欧氏距离）。定妆图必须**侧身朝右** + 附姿态参考图。⚠「会转的」和「不能转的」画同一张图 = 无解，必须拆件（halo / taiji，旋转整数圈，太极 S 曲线半圆圆心 `±r/2`）。长兵器独立成件 + 父 = arm + 手臂角 0.55 倍、轴放手握处（本项目武器在远侧，arm 关节负 x）。⚠ 场地中心贴花只画一次（别并进平铺贴图），定稿 660 + `decal_tint` 压暗。详见 `docs/美术资源接入记录.md`。
