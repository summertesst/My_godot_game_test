extends Enemy

# 敌人状态枚举
enum State {
	IDLE,    # 闲置状态
	WALK,    # 行走状态
	RUN,     # 奔跑状态
	HURT,    # 受伤状态
	DYING,   # 死亡状态
}

# 击退力度
const KNOCKBACK_AMOUNT := 512.0

# 变量声明
var pending_damage : Damage  # 待处理的伤害

# 节点引用
@onready var wall_checker: RayCast2D = $Graphics/WallChecker      # 墙壁检测射线
@onready var player_checker: RayCast2D = $Graphics/PlayerChecker  # 玩家检测射线
@onready var floor_checker: RayCast2D = $Graphics/FloorChecker    # 地面检测射线
@onready var calm_down_timer: Timer = $CalmDownTimer              # 冷静计时器

# 检查是否可以看到玩家
func can_see_player() -> bool:
	# 如果玩家检测射线没有碰撞到任何东西，返回false
	if not player_checker.is_colliding():
		return false
	# 检查碰撞到的对象是否是Player类型
	return player_checker.get_collider() is Player

# 物理处理 - 根据状态执行不同的物理行为
func tick_physics(state:State, delta:float) ->void:
	match state:
		State.IDLE, State.HURT, State.DYING:
			move(0.0 , delta)  # 这些状态下不移动
		State.WALK:
			move(max_speed /3 , delta)  # 行走状态下以1/3最大速度移动
		State.RUN:
			# 奔跑状态下，如果碰到墙壁或前方没有地面，则改变方向
			if wall_checker.is_colliding() or not floor_checker.is_colliding():
				direction *= -1
				
			# 以最大速度移动
			move(max_speed, delta)
			# 如果能看到玩家，启动冷静计时器
			if can_see_player():
				calm_down_timer.start()
	
# 获取下一个状态 - 状态机核心逻辑
func get_next_state(state: State) -> int:
	# 检查死亡条件
	if stats.health == 0:
		return StateMachine.KEEP_CURRENT if state == State.DYING else State.DYING
	
	# 检查是否有待处理伤害
	if pending_damage:
		return State.HURT
	
	# 状态特定转换逻辑
	match state:
		State.IDLE:
			# 如果看到玩家，转换为奔跑状态
			if can_see_player():
				return State.RUN
			# 闲置超过2秒，转换为行走状态
			if state_machine.state_time > 2:
				return State.WALK
		State.WALK:
			# 如果看到玩家，转换为奔跑状态
			if can_see_player():
				return State.RUN
			# 如果碰到墙壁或前方没有地面，转换为闲置状态
			if wall_checker.is_colliding() or not floor_checker.is_colliding():
				return State.IDLE
		State.RUN:
			# 如果看不到玩家且冷静计时器已停止，转换为行走状态
			if not can_see_player() and calm_down_timer.is_stopped():
				return State.WALK
			
		State.HURT:
			# 受伤动画结束后转换为奔跑状态
			if not animation_player.is_playing():
				return State.RUN

	# 默认保持当前状态
	return StateMachine.KEEP_CURRENT
	
# 状态转换处理
func transition_state(from: State, to: State) -> void:
	# 打印状态转换信息（用于调试）
	print("[%s] %s => %s" % [
		Engine.get_physics_frames(),
		State.keys()[from] if from != -1 else "<START>",
		State.keys()[to],
	])
	
	# 状态特定初始化逻辑
	match to:
		State.IDLE:
			animation_player.play("idle")  # 播放闲置动画
			# 如果碰到墙壁，改变方向
			if wall_checker.is_colliding():
				direction *= -1

		State.WALK:
			animation_player.play("walk")  # 播放行走动画
			# 如果前方没有地面，改变方向并强制更新射线检测
			if not floor_checker.is_colliding():
				direction *= -1
				floor_checker.force_raycast_update()
				
		State.RUN:
			animation_player.play("run")  # 播放奔跑动画
			
		State.HURT:
			animation_player.play("hit")  # 播放受伤动画
			
			# 应用伤害
			stats.health -= pending_damage.amount
			
			# 计算击退方向
			var dir := pending_damage.source.global_position.direction_to(global_position)
			# 应用击退速度
			velocity = dir * KNOCKBACK_AMOUNT
			
			# 根据击退方向调整敌人朝向
			if dir.x >0:
				direction = Direction.LEFT
			else:
				direction = Direction.RIGHT
				
			# 清空待处理伤害
			pending_damage = null
			
		State.DYING:
			animation_player.play("die")  # 播放死亡动画

# 受伤处理
func _on_hurtbox_hurt(hitbox: Hitbox) -> void:
	# 创建伤害对象
	pending_damage = Damage.new()
	pending_damage.amount = 1
	pending_damage.source = hitbox.owner
