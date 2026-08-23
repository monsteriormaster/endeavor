extends Node

## 全局事件总线。组件交互统一从这里广播，教学/剧情等系统订阅。

signal dialogue_finished

## 场景切换完成（change_scene 之后），参数为进入的场景路径
signal scene_entered(scene_path: String)
## 卡牌被放入卡槽。slot_name=卡槽名，card_id=卡 id，card_type=character/item
signal card_placed(slot_name: String, card_id: String, card_type: String)
## 触发器弹窗打开
signal trigger_opened(trigger_id: String)
## 触发器全流程结束
signal trigger_flow_completed(trigger_id: String, success: bool)
## 回合推进（玩家点「下一天」并完成结算后广播），参数为推进后的天数。
## 过天不再整场景重载（D-UI7），需要"每天跑一次"的逻辑请订阅本信号。
signal day_changed(day: int)
## 成就解锁（id=成就id，name=成就名）。由 AchievementManager 解锁时广播。
signal achievement_unlocked(id: String, name: String)
