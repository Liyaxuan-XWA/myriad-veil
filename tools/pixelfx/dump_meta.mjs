#!/usr/bin/env node
// 把 pixelfx 的特效 meta 导成 Godot 侧读的目录表。
//
//   node tools/pixelfx/dump_meta.mjs
//   node tools/pixelfx/dump_meta.mjs --lib E:/skill/game/pixelfx --out assets/fx/pixelfx/catalog.json
//
// 输出 assets/fx/pixelfx/catalog.json：
//   { library, generated, palettes: {fire:[hex...]}, effects: [{id, category, name, desc, tags,
//     size, origin, duration, loop, fps, actor, options, hits, windup}] }
// 面板只读这张表，不碰 JS；库更新后重跑本脚本即可。

import { join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { mkdirSync, writeFileSync } from "node:fs";

const PROJECT = resolve(fileURLToPath(import.meta.url), "..", "..", "..");
const args = process.argv.slice(2), flags = {};
for (let i = 0; i < args.length; i++) {
	if (args[i].startsWith("--")) flags[args[i].slice(2)] = args[++i];
}
const LIB = flags.lib ?? process.env.PIXELFX_HOME ?? "E:/skill/game/pixelfx";
const OUT = resolve(flags.out ?? join(PROJECT, "assets/fx/pixelfx/catalog.json"));

const fxlib = await import(pathToFileURL(join(LIB, "tools/lib/fxlib.mjs")).href);
const color = await import(pathToFileURL(join(LIB, "src/core/color.js")).href);

const effects = [];
const skipped = [];
for (const id of fxlib.allIds()) {
	let fx;
	try {
		fx = await fxlib.loadEffect(id);
	} catch (e) {
		skipped.push(`${id}: ${e.message}`);
		continue;
	}
	const m = fx.meta;
	const act = fx.mod.act;
	const hits = Array.isArray(act?.hits)
		? act.hits.map((h) => ({
			t: h.t, stop: h.stop ?? 0, shake: h.shake ?? 0,
			amp: h.amp ?? 0, push: h.push ?? 0, skin: h.skin ?? null,
		}))
		: [];
	const poses = Array.isArray(act?.poses) ? act.poses.map((p) => p[0]) : [];
	effects.push({
		id,
		category: id.split("/")[0],
		name: String(m.name ?? id),
		desc: String(m.desc ?? ""),
		tags: m.tags ?? [],
		size: m.size,
		origin: m.origin,
		duration: m.duration,
		loop: !!m.loop,
		fps: m.fps ?? 30,
		actor: !!m.actor,
		bg: m.bg ?? "ground",
		options: m.options ?? {},
		hits,
		windup: poses.length ? -Math.min(...poses.map((t) => (t < 0 ? -t : 0))) : 0,
	});
}
effects.sort((a, b) => a.id.localeCompare(b.id));

const palettes = {};
for (const [k, v] of Object.entries(color.PAL ?? {})) palettes[k] = v;

const doc = {
	library: "pixelfx",
	library_path: LIB.replace(/\\/g, "/"),
	generated: new Date().toISOString().slice(0, 19).replace("T", " "),
	palettes,
	count: effects.length,
	effects,
};
mkdirSync(join(OUT, ".."), { recursive: true });
writeFileSync(OUT, JSON.stringify(doc, null, 1));
console.log(`catalog ${effects.length} effects -> ${OUT}`);
if (skipped.length) console.log(`skipped ${skipped.length}: ${skipped.join(", ")}`);
