# Hitbox 类 - 用于检测攻击命中的区域
class_name Hitbox
extends Area2D  # 继承自 Area2D，用于检测区域重叠

# 信号定义 - 当命中 Hurtbox 时发出
signal hit(hurtbox)  # hurtbox: 被命中的 Hurtbox 对象

# 初始化函数
func _init() -> void:
	# 连接 area_entered 信号到自定义处理函数
	area_entered.connect(_on_area_entered)

# 区域进入处理函数
func _on_area_entered(hurtbox: Hurtbox) -> void:
	# 打印命中信息 [攻击者] => [被攻击者]
	print("[Hit] %s => %s" % [owner.name, hurtbox.owner.name])
	
	# 发出 hit 信号，传递被命中的 hurtbox
	hit.emit(hurtbox)
	
	# 触发 hurtbox 的 hurt 信号，传递自身作为攻击来源
	hurtbox.hurt.emit(self)
