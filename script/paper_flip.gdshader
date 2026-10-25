shader_type canvas_item;

// ============================================================================
//  翻页半平面裁切（2026-10-06）—— 网页稿 design/settings_panel/ 的 clip-path 的着色器版。
//
//  ▍它为什么必须挂在「页里的每一个 CanvasItem」上，而不是页根节点
//    Godot 的材质**不沿节点树继承**：给父 Control 挂 material，子节点照旧原样渲染。
//    所以由 `script/paper_flip.gd::_clip_tree()` 走一遍子树，把**同一个** ShaderMaterial
//    发给每个 CanvasItem —— 因为切的是同一条直线，逐项切 = 整页切。
//    （不用 CanvasGroup / clip_children 的理由：前者是 Node2D、Control 布局会飘；
//     后者要靠父节点自己画一个 alpha 遮罩，与本项目「父节点不画东西」的结构冲突。）
//
//  ▍🔴 为什么不能用 `UV`，必须把画布坐标当 varying 传下来（本文件踩过两次）
//    ① `UV` 是**每个 CanvasItem 自己盒子**的归一化坐标，不是屏幕坐标。
//       页里大部分节点都比屏幕小（涂鸦 400x300、按钮 192x58、每个 Label…），
//       拿 `UV * u_size` 当屏幕坐标 ⇒ 每个小节点各自「从自己左上角开始」算折线，
//       屏幕上会同时出现十几个方向各异的折线，而不是一条。
//       （网页稿里同一个坑：`clip-path` 的长度也相对元素自己的盒子 ——
//         `index.html` 里给 `.doodlewrap` 单独减掉 780/470 就是为了这个。）
//    ② `MODEL_MATRIX` **只在 vertex 函数里存在**，fragment 里用会直接
//       `SHADER ERROR: Unknown identifier in expression: 'MODEL_MATRIX'`，
//       整个材质编译失败（`_apply_clip` 照样把材质挂上去，于是「页面整个不显示」）。
//       ⇒ 只能 `vertex()` 里算好、用 varying 传给 `fragment()`。
//    `MODEL_MATRIX` 在 canvas_item 里是「本节点 → 画布」的完整变换（含所有父级），
//    所以 `MODEL_MATRIX * VERTEX` 就是**画布像素坐标**，与
//    `script/paper_fold.gd` 里那条折线（它是铺满屏幕的 Control，局部坐标 = 画布坐标）同源。
//    ⚠️ 刻意**不乘** `CANVAS_MATRIX`：那一步会带上窗口缩放，
//      本工程的布局坐标恒为 1920x1080，乘了反而在窗口化调试时对不上。
//
//  ▍折线
//      fold(v) = u_fold + u_tilt * (1 - 2v)          v = 画布 y / u_size.y
//        v=0（顶边）→ u_fold + u_tilt  ⇒ 顶边超前（读作「右上角先落」）
//        v=1（底边）→ u_fold - u_tilt
//      `u_side = +1` 保留折线**左侧**（要翻进来的那一页在左）；
//      `u_side = -1` 保留**右侧**（被翻走的那一页在右）。
//
//  ▍为什么是 `COLOR.a *=` 而不是 `discard`
//    discard 做不出 1px 抗锯齿边，纸页那条直边会变成锯齿 ——
//    本项目口径是「不许出现硬边」（一出现立刻读成「电子味」）。
//    这里用 clamp(d, 0, 1) 给一条 1px 的线性过渡，肉眼即平滑。
//    （`d` 是像素量、不是 UV ⇒ 这条过渡带恒为 1px，与节点大小无关。）

uniform float u_fold = -4000.0;
uniform float u_tilt = 15.0;
uniform float u_side = 1.0;
uniform vec2 u_size = vec2(1920.0, 1080.0);

// 画布像素坐标。只能在 vertex 里算（见上面 ②）。
varying vec2 v_cpos;

void vertex() {
	v_cpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float fold = u_fold + u_tilt * (1.0 - 2.0 * v_cpos.y / u_size.y);
	float d = (fold - v_cpos.x) * u_side;   // >0 = 该保留
	COLOR.a *= clamp(d, 0.0, 1.0);
}
