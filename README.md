# endeavor
我们的目的主要还是做个尝试啦

debug里的文件随便折腾。

script里放纯代码文件，比如我建立了一个dialogue.gd的文件用来创建单个对话的类。

component里存放组件，比如对话框，角色面板，大场景中会调用的小场景。

addons插件，比如我们现在用的FSM。

plot是情节文件，格式参照test文件。

resoures里是json文件，也是游戏中的各种静态信息存放的地方，包括剧情，剧情触发配置等等。

map是从组件中独立出来的，用于存放每个场景的地点情况。

art是些美术资源。


## 一些文件的介绍
res://script/player.gd
游戏过程中的变量，内有详细说明

res://script/plot_importer.gd
剧情处理器
调用剧情实例:
	PlotImporter.add_plot("res://resoures/plot/rite/prison.json","伤痕后与衫斯的交流")


res://components/main_ui.tscn
主要游戏界面的ui
调用方式:
	1、
	在根节点右键点击实例化子节点选择该文件
	2、
	var ui = load("res://components/main_ui.tscn").instantiate()
	add_child(ui)
	
	
res://components/character.tscn
界面中科对话的人物
调用方式:
	在根节点右键点击实例化子节点选择该文件，在检查器中设置属性charcter_name、config_path


res://components/confirmdialog.tscn
确认框
调用方式:
	var confirm_dialog = load("res://components/confirmdialog.tscn").instantiate()
		confirm_dialog.setup(
			"确认离开",
			"有资质没有用完，确定要离开吗？",
			"确认",
			"返回"
			)
		confirm_dialog.confirmed.connect(before_trans)
		remove_child(confirm_dialog)
		add_child(confirm_dialog)
