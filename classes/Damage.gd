# 创建 Damage 实例
class_name Damage
extends RefCounted # 继承自 RefCounted，表示这是一个可自动管理内存的引用计数对象

# 伤害属性
var amount : int # 伤害数值，表示造成的伤害量
# 伤害来源
var source: Node2D# 造成伤害的源对象，通常是 Node2D 类型的节点（如玩家、敌人等）
