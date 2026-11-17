#!/usr/bin/env node
// 把 pixelfx 特效烘焙成 Godot 用的透明序列帧表（Aseprite 格式 JSON + PNG）。
//
//   node tools/pixelfx/bake.mjs ice/frost-nova
//   node tools/pixelfx/bake.mjs ice/frost-nova --palette fire --variant fire_ing
//   node tools/pixelfx/bake.mjs fire/torch --set reach=120 --seed 7 --fps 24
//   node tools/pixelfx/bake.mjs --jobs bake_jobs.json
//   node tools/pixelfx/bake.mjs melee --all-in-category
//
// 产物：assets/fx/pixelfx/<category>/<name>__<variant>.png / .json
// 每成功一个打印一行 BAKE_OK ...，失败打印 BAKE_FAIL ...，Godot 面板按这两行回执。
// 默认**不含**那个灰色小人（meta.actor 只是它的取景参考），要带角色加 --actor。

import { join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";

const PROJECT = resolve(fileURLToPath(import.meta.url), "..", "..", "..");
const args = process.argv.slice(2), flags = {}, ids = [];
for (let i = 0; i < args.length; i++) {
	const a = args[i];
	if (!a.startsWith("--")) ids.push(a);
	else if (["actor", "all-in-category", "quiet"].includes(a.slice(2))) flags[a.slice(2)] = true;
	else {
		const key = a.slice(2), val = args[++i];
		// --set 可重复，其它取最后一个
		if (key === "set") (flags.set ??= []).push(val);
		else flags[key] = val;
	}
}
const LIB = flags.lib ?? process.env.PIXELFX_HOME ?? "E:/skill/game/pixelfx";
const OUT = resolve(flags.out ?? join(PROJECT, "assets/fx/pixelfx"));
if (!existsSync(LIB)) {
	console.log(`BAKE_ERR pixelfx 库不在 ${LIB}（克隆后放到这里，或 --lib 指过去）`);
	process.exit(2);
}

const fxlib = await import(pathToFileURL(join(LIB, "tools/lib/fxlib.mjs")).href);
const color = await import(pathToFileURL(join(LIB, "src/core/color.js")).href);

// --set k=v 可重复；值只认数字、true/false、逗号分隔的 hex 色带
const extra = {};
for (const raw of flags.set ?? []) {
	const s = String(raw), eq = s.indexOf("=");
	if (eq < 1) continue;
	const key = s.slice(0, eq).trim(), val = s.slice(eq + 1).trim();
	if (val === "true" || val === "false") extra[key] = val === "true";
	else if (!Number.isNaN(Number(val))) extra[key] = Number(val);
	else if (val.startsWith("#")) extra[key] = val.split(",");
	else extra[key] = val;
}

function resolvePalette(p) {
	if (!p) return null;
	if (p.startsWith("#")) return p.split(",").map((s) => s.trim());
	if (color.PAL?.[p]) return color.PAL[p];
	console.log(`BAKE_WARN 未知色带 "${p}"，用特效默认色带`);
	return null;
}

const jobs = [];
if (flags.jobs) {
	for (const j of JSON.parse(readFileSync(resolve(flags.jobs), "utf8"))) jobs.push(j);
}
for (const id of fxlib.resolveIds(ids.length ? ids : [])) {
	jobs.push({
		id,
		variant: flags.variant ?? (flags.palette ? String(flags.palette).replace(/[^0-9a-z_#-]/gi, "") : "default"),
		palette: flags.palette, seed: flags.seed, fps: flags.fps, actor: !!flags.actor, set: extra,
	});
}

let failed = 0;
for (const job of jobs) {
	const short = String(job.id).split("/")[1];
	const variant = String(job.variant ?? "default");
	const base = `${short}__${variant}`;
	try {
		const fx = await fxlib.loadEffect(job.id);
		const options = { ...(job.set ?? {}) };
		const pal = resolvePalette(job.palette);
		if (pal) options.palette = pal;
		const r = fxlib.renderFrames(fx, {
			fps: job.fps ? Number(job.fps) : undefined,
			seed: job.seed !== undefined && job.seed !== "" ? Number(job.seed) : undefined,
			actor: job.actor ? undefined : false,
			options: Object.keys(options).length ? options : undefined,
		});
		const s = fxlib.spriteSheet(fx, r, base);
		s.json.meta.pixelfx.variant = variant;
		s.json.meta.pixelfx.effect_id = job.id;
		s.json.meta.pixelfx.options = options;
		s.json.meta.pixelfx.baked_at = new Date().toISOString().slice(0, 19).replace("T", " ");
		const dir = join(OUT, String(job.id).split("/")[0]);
		mkdirSync(dir, { recursive: true });
		fxlib.save(join(dir, `${base}.png`), s.png);
		writeFileSync(join(dir, `${base}.json`), JSON.stringify(s.json, null, 1));
		const m = s.json.meta.pixelfx;
		// 落在项目 assets 里才报 res:// 路径；烘到预览区（user:// 等外部目录）时报真实绝对路径，
		// 免得面板拿着一个不存在的 res:// 路径去 reimport
		const assetRoot = resolve(join(PROJECT, "assets/fx/pixelfx"));
		const inside = resolve(OUT).startsWith(assetRoot);
		const rel = inside
			? `res://assets/fx/pixelfx/${String(job.id).split("/")[0]}/${base}`
			: join(OUT, String(job.id).split("/")[0], base).replace(/\\/g, "/");
		console.log(`BAKE_OK ${job.id} ${variant} ${rel}.png ${m.frames} ${m.fps} ` +
			`${m.frameSize[0]} ${m.frameSize[1]} ${m.columns} ${m.pivot[0]} ${m.pivot[1]} ${m.loop ? "loop" : "once"}`);
	} catch (e) {
		failed++;
		console.log(`BAKE_FAIL ${job.id} ${String(e.message ?? e).replace(/\s+/g, " ").slice(0, 160)}`);
	}
}
process.exit(failed ? 1 : 0);
