# Enemy 类 - 敌人角色的基类，继承自 CharacterBody2D
class_name Enemy
extends CharacterBody2D

# 方向枚举 - 定义敌人的移动方向
enum Direction {
	LEFT = -1,   # 向左移动
	RIGHT = +1,  # 向右移动
}

# 导出变量 - 可以在编辑器中设置
@export var direction := Direction.LEFT:  # 当前移动方向
	set(v):  # 设置器，当方向改变时自动更新图形朝向
		direction = v
		if not is_node_ready():  # 如果节点尚未准备就绪
			await ready         # 等待节点准备就绪
		graphics.scale.x = - direction  # 更新图形朝向（负号是因为图形默认朝向右边）

@export var max_speed : float = 180      # 最大移动速度
@export var acceleration :float = 2000   # 加速度

# 重力设置
var default_gravity := ProjectSettings.get("physics/2d/default_gravity") as float  # 从项目设置获取默认重力值

# 节点引用
@onready var graphics: Node2D = $Graphics                    # 图形节点，用于控制角色朝向
@onready var animation_player: AnimationPlayer = $AnimationPlayer  # 动画播放器
@onready var state_machine: StateMachine = $StateMachine          # 状态机
@onready var stats: Stats = $Stats                                # 属性统计节点

# 移动函数 - 处理敌人的物理移动
func move(speed:float, delta:float) ->void:
	# 计算水平速度：向目标速度加速移动
	velocity.x = move_toward(velocity.x, speed * direction, acceleration * delta)
	# 应用重力
	velocity.y += default_gravity * delta
	
	# 执行移动并处理碰撞
	move_and_slide()
