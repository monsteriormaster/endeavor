## 地图色温层（M-SUN1 v2，2026-10-17）
##
## 一个盖在主城地图上、UI 之下的 ColorRect，每帧读 `SunClock.tint_color()`：
## 正午近乎无色 → 清晨/黄昏偏暖橙 → 夜偏蓝灰（alpha 上限 0.13）。
## 只到「读得出天色」的程度 —— 这是氛围，不是滤镜，压过建筑颜色就过了。
##
## ⚠️ 只挂在 `scene/main.tscn`（主城）。二级地图是室内/近景，不放（已拍板）。
## mouse_filter 必须 IGNORE：这一层横跨整屏，吃了输入地图就点不动了。
##
## 🔴 遮挡靠 z_index，不靠树序（2026-10-21 修）
##   `DayTint.z_index = 1` + `Main_ui.z_index = 2`，两者都写在 `scene/main.tscn` 里。
##
##   起因：玩家报「图标与地图之间有一块淡淡的方形色差」。它一度是 `background`
##   的子节点 —— 只染底图、不染 `FirstCity` 的十张图标。清晨那档 alpha 本来就低
##   （0.10），叠到纸色 (231,216,194) 上是 **(+2.4, −3.2, −7.9)**：红涨、蓝塌。
##   底图吃了这一口、图标没吃，两者差出一个方块。
##
##   ⚠️ 别指望「把这一层挪到 `FirstCity` 后面」能解决 —— 实测挪了没用，连
##   `FirstCity.visible = false` / `modulate.a = 0` / 平移 400px 都**一个像素都不变**
##   （记录在 `debug/_find_drawers.gd`）。这个版本里只有 `z_index` 是可靠的遮挡手段。
##
##   光该照在整幅地图上：底图、涂鸦、影子、图标、触发器徽章，同一束光。
##   UI（顶栏 / 手牌区）不参与光照，所以 `Main_ui` 必须压在它上面（z=2）。
##
##   回归：`design/_tools/check_tint_uniform.py`（框内外受光差 < 0.8 级为 PASS，
##   实测 0.10 级）。
extends ColorRect


func _process(_delta: float) -> void:
	color = SunClock.tint_color()
