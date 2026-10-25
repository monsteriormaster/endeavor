shader_type canvas_item;
render_mode blend_mix;

// ─────────────────────────────────────────────────────────────────────────────
//  ⚠️ 已退役（2026-09-29，M-ANI2 v3）—— 文件保留、**没有任何代码引用它**。
//     v3 把过场换成「原场景淡出 → 新场景淡入」（旧画面快照交叉溶解，
//     见 script/scene_transition.gd），因此不再需要任何过场材质。
//     本文件里的 `SceneTransition._needed_radius()` 等接口在 v3 已删除；
//     五个 uniform 的标定值保留仅供将来重新启用时参考（详见 GDD §5.1「已退役」段）。
//     重新启用前请先读那段，尤其「mix() 在线性空间」那一条。
//
//  铅笔纸面过场（M-ANI2 v2）
//  挂在一个全屏 ColorRect 上，由 autoload `SceneTransition` 驱动三个 uniform。
//
//  ▍为什么重做（v1「墨晕」被否）
//    v1 是一块近黑墨渍 + 平滑正圆边，读起来是「数字遮罩」，和本作彩铅 + 纸张的画面
//    材质根本不是同一种东西 —— 从彩铅地图上点一下，突然糊上来一块电子黑，材质对不上，
//    所以「突兀」。参考《重返未来 1999》的做法：连黑屏读条都要往里画点东西，纯色遮罩
//    本身就是「敷衍」。v2 换成同源材质，让过场读作「一张纸被铺上 / 抽走」：
//      暖纸色底 + 极淡方格制图网 + 纸纹颗粒 + 45° 铅笔排线带 + 手绘毛边与出界毛刺。
//    边界因此是「一支铅笔正在涂」，而不是「一圈遮罩正在放大」。
//
//  ▍为什么不是纯圆
//    半径叠三条谐波 + 一层 value noise，幅度正比于当前半径（R→0 时扰动归零，
//    起手不会在点击处留一小团残渣）。边界内侧再叠一条 45° 排线带，等于笔尖的
//    「涂抹区」；带外随机戳出短毛刺，是手画出界的自然结果。
//
//  uniform 语义
//    cover  : 0 = 完全透明；1 = 纸面铺满全屏
//    center : 纸面圆心。揭幕阶段由 SceneTransition 往外推 → 整张纸像被抽走，
//             而不是收缩成一个点（收缩会读成「虹膜遮罩」，那是 v1 的毛病）
//    fade   : 纸面整体不透明度。揭幕末段下降 → 透出下面已换好的新场景
//             （半透明纸叠化，参考《迷雾中的马戏团》的硫酸纸转场）
// ─────────────────────────────────────────────────────────────────────────────

/// 纸面推进进度。
uniform float cover : hint_range(0.0, 1.0) = 0.0;
/// 铺满全屏所需的边界半径。**不是常数** —— 由 SceneTransition._needed_radius()
/// 按本次起点算出来后写入。实测 10 个主城图标：最小 1.374（教会）、最大 2.073（孤儿院）。
/// 起点越靠角，需要的半径越大（要够到最远那个屏幕角）。
/// hint_range 上限给到 3.0：2.0 会在检视器里把真实值（2.073）显示成越界，误导改参数的人。
uniform float radius : hint_range(0.5, 3.0) = 1.30;
/// 纸面圆心（视口归一化坐标 0..1）。
uniform vec2 center = vec2(0.5, 0.5);
/// 视口宽高比：UV 的 x 先乘它，圆才不会被 16:9 拉成椭圆。
uniform float aspect = 1.777778;
/// 边界软度（相对 radius）。太大就成了「光晕」，这里只要够糊住锯齿。
/// 标定：1.0 半径 ≈ 1080px，0.055 → 约 77px 软边。
uniform float feather : hint_range(0.005, 0.4) = 0.055;
/// 排线带宽度（相对 radius）：笔尖涂抹区的宽度。0.14 → 约 197px。
uniform float band_w : hint_range(0.0, 0.5) = 0.14;
/// 毛边抖动强度（1.0 = 标定值）。
uniform float wobble : hint_range(0.0, 3.0) = 1.0;
/// 纸面整体不透明度。1 = 实心纸，0 = 完全透出。
uniform float fade : hint_range(0.0, 1.0) = 1.0;

/// 纸色。**实测标定**：主城底色是暖奶油（均值 sRGB 212,205,185 ≈ 亮度 206），
/// 所以纸不能只「比底亮一点」，否则盖上纸等于什么都没发生。这里取偏冷的近白
/// （248,246,242 ≈ 亮度 246，Δ≈40 且色相从暖翻冷），读作「又铺了一张新纸」。
uniform vec3 paper_col : source_color = vec3(0.972, 0.965, 0.949);
/// 笔色（石墨褐，不是纯黑 —— 彩铅的线永远是带色的暗，纯黑会立刻出「数码味」）。
/// 亮度 74，与底色 206 对比 Δ132，笔圈 / 排线都立得住。
uniform vec3 ink_col : source_color = vec3(0.278, 0.259, 0.235);


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


void fragment() {
	// 等比空间：p.x 已乘 aspect，于是「圆」在任何窗口比例下都是圆
	vec2 p = (UV - center) * vec2(aspect, 1.0);
	float dist = length(p);
	float ang = atan(p.y, p.x);

	float R = cover * radius;

	// 手绘毛边：三频谐波（低/中/高频各一，模拟手腕、指节、笔尖三层不稳定）
	// + 一层噪声（擦掉正弦的机械感）。幅度乘 R，保证 R→0 时扰动同时归零。
	// 幅度合计约 ±14%：再大就不是「一支笔在圈」，而是一坨形状不明的墨。
	float wob = R * wobble * (
			 0.058 * sin(ang * 3.0 + 1.7)
			+ 0.034 * sin(ang * 7.0 - 0.6)
			+ 0.021 * sin(ang * 13.0 + 2.4)
			+ 0.075 * (vnoise(vec2(ang * 5.0, 2.0)) - 0.5));
	float r = R + wob;
	float fw = feather * radius + 0.004;

	// paper：1 = 被纸盖住。inner：把边界往里收 band_w → 两者之差就是「笔尖涂抹带」
	float paper = 1.0 - smoothstep(r - fw, r + fw, dist);
	float inner = 1.0 - smoothstep(r - band_w * radius - fw * 0.6,
								   r - band_w * radius + fw, dist);
	float bandm = clamp(paper - inner, 0.0, 1.0);

	// 起手压暗：cover 还没长过边界宽度时整体归零，保证 cover==0 屏幕上空无一物
	float onset = clamp(R / (fw * 2.0), 0.0, 1.0);
	paper *= onset;
	bandm *= onset;

	// ── 纸：近白 + 极淡方格制图网 + 纸纹颗粒 ──
	// 方格是「制图纸」的记忆点，也是替掉「黑屏」的关键 —— 停留阶段屏幕上不是空的。
	// ⚠️ 格线场必须用 **max**（沿整条格边为 1、格心为 0），**不能用 min**：
	//   `min` 只在「格子四角交点」附近等于 1 → 格线面积只占 0.64%，纸上看不出格子。
	//   用 max 后格线面积 = 1-(1-0.08)² ≈ 15%，是与 46 格匹配的细线。
	// ⚠️ 也**不能**写成 `1 - smoothstep(0.86,1.0,gd)`（那是把 92% 的面积都压暗）：
	//   纸面均值会从设计的 246 掉到实测 225，与地图底色 207 只差 18，盖上几乎看不出。
	vec2 gp = UV * vec2(aspect, 1.0) * 46.0;
	float gd = max(abs(fract(gp.x) - 0.5), abs(fract(gp.y) - 0.5)) * 2.0;
	float grid = smoothstep(0.92, 1.0, gd);
	float grain = vnoise(UV * vec2(aspect, 1.0) * 360.0);
	// 颗粒均值 = 0.975 + 0.035*0.5 = 0.9925 → 纸基色基本就是 paper_col（实测均值亮度 245）
	vec3 pc = paper_col * (0.975 + 0.035 * grain);
	// 格线单独压深。**注意混色发生在线性空间**：ink_col 的线性值只有 0.062，
	// 而纸的线性值约 0.93 —— 按 0.20 混出来只掉到 sRGB 229（Δ16，等于看不见）；
	// 取 0.40 才落到 sRGB 约 211（Δ34，细线清楚但不吵）。整屏均值只掉 ~3%。
	pc = mix(pc, ink_col, 0.40 * grid * (0.55 + 0.45 * grain));

	// ── 排线带：45° 铅笔涂抹，疏密不均 ──
	// 频率 70：全屏约 137 条 → 线距约 7.9px。
	// 占空比取 30%（`smoothstep(0, 0.30, tri)`）→ 线宽约 2.4px、间隙约 5.5px。
	// **不能取到 50%**：50% 占空比在 8px 尺度上直接糊成一块 50% 灰，读作「脏」而不是「排线」。
	float hp = dot(p, vec2(0.70711, 0.70711)) * 70.0;
	float tri = abs(fract(hp) - 0.5) * 2.0;
	float stroke = 1.0 - smoothstep(0.0, 0.30, tri);
	// 沿线条方向让密度起伏 → 断断续续，不是规则网纹
	stroke *= 0.35 + 0.85 * vnoise(vec2(hp * 0.10, ang * 2.3));

	// 出界毛刺：只出现在边界附近的一圈，随机往外戳的短笔尖。
	// 用 abs(dist - r) 取「以边界为中心的窄带」，不能写成单向 smoothstep ——
	// 写成单向会把毛刺铺满整张纸内部，读起来是脏点而不是出界。
	// 带宽 fw*0.9（约 ±73px）→ 是一圈毛边，不是一条厚带。
	float scuff_band = 1.0 - smoothstep(0.0, fw * 0.9, abs(dist - r));
	float scuff = step(0.88, vnoise(vec2(ang * 34.0, floor(dist * 46.0))));
	float scuff_m = scuff_band * scuff * onset;

	vec3 col = mix(pc, mix(pc, ink_col, clamp(stroke * 0.62, 0.0, 0.68)),
			clamp(bandm, 0.0, 1.0));
	col = mix(col, ink_col * 0.9, scuff_m * 0.45);

	// 毛刺在纸外没有纸托底，靠自己的 alpha 立住（否则会是一条条实心方块）
	float a = clamp(paper + scuff_m * 0.50, 0.0, 1.0);
	COLOR = vec4(col, a * fade);
}
