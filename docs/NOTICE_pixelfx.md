# pixelfx 素材的许可与归属

本项目里的 `assets/fx/pixelfx/**` 是用 [pixelfx](https://github.com/patch-gg/pixelfx) 烘焙出来的派生产物，
随项目发布的序列帧表属于**衍生作品**，需保留以下归属。

## 许可

MIT License — Copyright (c) 2026 Patch；Copyright (c) 2026 Hugo Duprez。
完整条款见库根目录 `LICENSE`（`E:/skill/game/pixelfx/LICENSE`）。

## 库自己的 NOTICE（照抄自上游 `NOTICE.md`）

- **Hugo Duprez** — `src/core/sim.js` 以及文件头注明的那些特效，改编自 Sprite Fusion 的开源像素 VFX
  （<https://www.spritefusion.com/pixel-art-vfx>），Copyright (c) 2026 Hugo Duprez，MIT。
- **Hollow Crown** — `src/core/act.js` 的角色出招演法（12fps 姿势步、命中停顿、草人受击）改编自
  <https://github.com/rehan-remade/hollow-crown>，Copyright (c) 2026 rehan-remade，MIT。
- **Patch Pixel 字体** — 库内 `gallery/fonts` 的字体**不在** MIT 覆盖范围内。
  本项目不使用该字体，UI 仍用 `assets/fonts` 里自己的字体。

## 本项目的用法边界

- 只烘焙进 PNG/JSON 序列帧表，不复制任何 `.js` 源码进游戏仓库。
- pixelfx 库本体放在游戏仓库之外（默认 `E:/skill/game/pixelfx`），换机器时重新克隆即可：
  `git clone --depth 1 https://github.com/patch-gg/pixelfx.git E:/skill/game/pixelfx`
- 若要发布商业版本，把本文件一并打进致谢/开源许可页。
