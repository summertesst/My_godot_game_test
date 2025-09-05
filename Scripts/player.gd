class_name Player
extends CharacterBody2D

# 玩家状态枚举
enum State{
	IDLE,           # 闲置状态
	RUNNING,        # 奔跑状态
	JUMP,           # 跳跃状态
	FALL,           # 下落状态
	LANDING,        # 着陆状态
	WALL_SLIDING,   # 墙面滑行状态
	WALL_JUMP,      # 墙面跳跃状态
	ATTACK_1,       # 攻击1状态
	ATTACK_2,       # 攻击2状态
	ATTACK_3,       # 攻击3状态
	HURT,           # 受伤状态
	DYING,          # 死亡状态
	SLIDING_START,
	SLIDING_LOOP,
	SLIDING_END,
}

# 地面状态列表（这些状态下玩家被视为在地面上）
const GROUND_STATES := [
	State.IDLE, State.RUNNING, State.LANDING,
	State.ATTACK_1, State.ATTACK_2, State.ATTACK_3,
	]

# 移动参数
const RUN_SPEED: = 160.0                       # 奔跑速度
const FLOOR_ACCELARATION:= RUN_SPEED /0.2      # 地面加速度
const AIR_ACCELARATION:= RUN_SPEED /0.1        # 空中加速度
const JUMP_VELOCITY := -320.0                  # 跳跃速度（负值表示向上）
const WALL_JUMP_VELOCITY := Vector2(450, -280) # 墙面跳跃速度
const KNOCKBACK_AMOUNT := 512.0                # 击退力度
const SLDING_DURATION := 0.3
const SLIDING_SPEED := 256.0
const SLIDING_ENERGY := 4.0
const LANDING_HIGHT := 100.0

# 导出变量
@export var can_combo : = false  # 是否可以连击

# 变量声明
var default_gravity :=ProjectSettings.get("physics/2d/default_gravity") as float  # 默认重力
var is_first_tick := false       # 是否是状态的第一帧
var is_combo_requested := false  # 是否请求了连击
var pending_damage : Damage      # 待处理的伤害
var fall_from_y :float 
var interacting_with : Array[Interactable]

# 节点引用
@onready var graphics: Node2D = $Graphics
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var jump_request_timer: Timer = $JumpRequestTImer
@onready var hand_checker: RayCast2D = $Graphics/HandChecker
@onready var foot_checker: RayCast2D = $Graphics/FootChecker
@onready var state_machine: StateMachine = $StateMachine
@onready var stats: Stats = $Stats
@onready var invincible_timer: Timer = $InvincibleTimer
@onready var slide_request_timer: Timer = $SlideRequestTImer
@onready var interaction_icon: AnimatedSprite2D = $InteractionIcon


# 输入处理
func _unhandled_input(event: InputEvent) -> void:
	# 跳跃输入处理
	if event.is_action_pressed("jump"):
		jump_request_timer.start()
	
	# 跳跃释放处理（实现可变高度跳跃）
	if event.is_action_released("jump"):
		jump_request_timer.stop()
		if velocity.y < JUMP_VELOCITY /2:
			velocity.y=JUMP_VELOCITY /2
			
	# 攻击输入处理
	if event.is_action_pressed("attack") and can_combo:
		is_combo_requested = true
		
	if event.is_action_pressed("slide"):
		slide_request_timer.start()
		
	if event.is_action_pressed("interact") and interacting_with:
		interacting_with.back().interact()
	
# 物理处理 - 根据状态执行不同的物理行为
func tick_physics(state: State,delta: float) -> void:
	interaction_icon.visible = not interacting_with.is_empty()
	
	if invincible_timer.time_left >0 :
		graphics.modulate.a = sin(Time.get_ticks_msec() / 20 )*0.5 +0.5
	else:
		graphics.modulate.a = 1
	
	match  state:
		State.IDLE:
			move(default_gravity,delta)  # 闲置状态下可以移动
			
		State.RUNNING:
			move(default_gravity,delta)  # 奔跑状态下移动
			
		State.JUMP:
			# 跳跃状态：第一帧无重力，之后应用重力
			move(0.0 if is_first_tick else default_gravity, delta)
			
		State.FALL:
			move(default_gravity,delta)  # 下落状态下应用重力移动
			
		State.LANDING:
			stand(default_gravity,delta)  # 着陆状态下站立
			
		State.WALL_SLIDING:
			# 墙面滑行：应用1/4重力，调整朝向
			move(default_gravity /4 ,delta)
			graphics.scale.x = -get_wall_normal().x
			
		State.WALL_JUMP:
			# 墙面跳跃：前0.1秒站立，之后正常移动
			if state_machine.state_time < 0.1:
				stand(0.0 if is_first_tick else default_gravity,delta)
				graphics.scale.x = get_wall_normal().x
			else:
				move(default_gravity, delta)
				
		State.ATTACK_1, State.ATTACK_2, State.ATTACK_3:
			stand(default_gravity, delta)  # 攻击状态下站立
			
		State.HURT, State.DYING:
			stand(default_gravity, delta)  # 受伤和死亡状态下站立
			
		State.SLIDING_END:
			stand(default_gravity, delta)
			
		State.SLIDING_LOOP, State.SLIDING_START:
			slide(delta)
			
	is_first_tick = false  # 标记第一帧结束

# 移动函数
func move(gravity: float, delta: float) ->void:
	# 获取输入方向
	var direction := Input.get_axis("move_left","move_right" )
	# 根据是否在地面选择加速度
	var acceleration :=FLOOR_ACCELARATION if is_on_floor() else AIR_ACCELARATION
	# 计算水平速度
	velocity.x = move_toward(velocity.x, direction * RUN_SPEED, acceleration *delta)
	# 应用重力
	velocity.y +=gravity * delta
	
	# 根据方向调整角色朝向
	if not is_zero_approx(direction):
		graphics.scale.x = -1 if direction < 0 else +1
	# 执行移动
	move_and_slide()

func slide(delta: float) ->void:
	velocity.x = graphics.scale.x * SLIDING_SPEED
	velocity.y +=  default_gravity * delta
	
	move_and_slide()

# 检查是否可以墙面滑行
func can_wall_slide() -> bool:
	return is_on_wall() and hand_checker.is_colliding() and foot_checker.is_colliding()

func should_slide() -> bool:
	if slide_request_timer.is_stopped():
		return false
	if stats.energy < SLIDING_ENERGY:
		return false
	
	return not foot_checker.is_colliding()

# 站立函数（不移动但应用重力）
func stand(gravity:float, delta:float) ->void:
	# 根据是否在地面选择加速度
	var acceleration :=FLOOR_ACCELARATION if is_on_floor() else AIR_ACCELARATION
	# 逐渐减少水平速度
	velocity.x = move_toward(velocity.x, 0.0, acceleration *delta)
	# 应用重力
	velocity.y +=gravity * delta
	# 执行移动
	move_and_slide()

func die() -> void:
	get_tree().reload_current_scene()

func register_interactable(v:Interactable ) -> void:
	if state_machine.current_state == State.DYING:
		return
	if v in interacting_with:
		return
	interacting_with.append(v)

func unregister_interactable(v : Interactable) ->void:
	interacting_with.erase(v)

# 获取下一个状态 - 状态机核心逻辑
func get_next_state(state: State) -> int:
	# 检查死亡条件
	if stats.health == 0:
		return StateMachine.KEEP_CURRENT if state == State.DYING else State.DYING
	
	# 检查是否有待处理伤害
	if pending_damage:
		return State.HURT
	
	# 跳跃条件检查（地面或土狼时间内）
	var can_jump := is_on_floor() or coyote_timer.time_left >0
	var should_jump := can_jump and Input.is_action_just_pressed("jump")
	if should_jump:
		return StateMachine.KEEP_CURRENT if state == State.JUMP else State.JUMP
	
	# 从地面状态切换到下落状态
	if state in GROUND_STATES and not is_on_floor():
		return State.FALL
	
	# 获取移动方向和静止状态
	var direction := Input.get_axis("move_left","move_right" )
	var is_still := is_zero_approx(direction) and is_zero_approx(velocity.x)
	
	# 状态特定转换逻辑
	match state:
		State.IDLE:
			if Input.is_action_just_pressed("attack"):
				return State.ATTACK_1
			if should_slide():
				return State.SLIDING_START
			if not is_still:
				return State.RUNNING
		
		State.RUNNING:
			if Input.is_action_just_pressed("attack"):
				return State.ATTACK_1
			if should_slide():
				return State.SLIDING_START
			if is_still:
				return State.IDLE
		
		State.JUMP:
			if velocity.y >=0:  # 速度向下时转换为下落状态
				return State.FALL
		
		State.FALL:
			if is_on_floor():  # 落地时转换为着陆或奔跑状态
				var height := global_position.y - fall_from_y
				return State.LANDING if height >= LANDING_HIGHT else State.RUNNING
			if can_wall_slide():  # 可以墙面滑行时转换
				return State.WALL_SLIDING
		
		State.LANDING:
			if not animation_player.is_playing():  # 动画结束后转换为闲置
				return State.IDLE
				
		State.WALL_SLIDING:
			if jump_request_timer.time_left > 0:  # 有跳跃请求时墙面跳跃
				return State.WALL_JUMP
			if is_on_floor():  # 落地时转换为闲置
				return State.IDLE
			if not is_on_wall():  # 离开墙面时转换为下落
				return State.FALL
		
		State.WALL_JUMP:
			if can_wall_slide() and not is_first_tick:  # 可以墙面滑行时转换
				return State.WALL_SLIDING
			if velocity.y >=0:  # 速度向下时转换为下落
				return State.FALL
		
		State.ATTACK_1:
			if not animation_player.is_playing():  # 动画结束后根据连击请求转换
				return State.ATTACK_2 if is_combo_requested else State.IDLE
				
		State.ATTACK_2:
			if not animation_player.is_playing():  # 动画结束后根据连击请求转换
				return State.ATTACK_3 if is_combo_requested else State.IDLE
			
		State.ATTACK_3:
			if not animation_player.is_playing():  # 动画结束后转换为闲置
				return State.IDLE
				
		State.HURT:
			if not animation_player.is_playing():  # 动画结束后转换为闲置
				return State.IDLE
	
		State.SLIDING_START:
			if not animation_player.is_playing():  
				return State.SLIDING_LOOP
					
				
		State.SLIDING_END:
			if not animation_player.is_playing():  
				return State.IDLE
		
		State.SLIDING_LOOP:
			if state_machine.state_time > SLDING_DURATION or is_on_wall():
				return State.SLIDING_END
	# 默认保持当前状态
	return StateMachine.KEEP_CURRENT
	
# 状态转换处理
func transition_state(from: State, to: State) -> void:
	# 打印状态转换信息（用于调试）
	#print("[%s] %s => %s" % [
		#Engine.get_physics_frames(),
		#State.keys()[from] if from != -1 else "<START>",
		#State.keys()[to],
	#])
	#
	# 从非地面状态转换到地面状态时停止土狼计时器
	if from not in GROUND_STATES and to in GROUND_STATES:
		coyote_timer.stop()
		
	# 状态特定初始化逻辑
	match to:
		State.IDLE:
			animation_player.play("idle")
		State.RUNNING:
			animation_player.play("running")
		State.JUMP:
			animation_player.play("jump")
			velocity.y = JUMP_VELOCITY  # 设置跳跃速度
			coyote_timer.stop()         # 停止土狼计时器
			jump_request_timer.stop()   # 停止跳跃请求计时器
		State.FALL:
			animation_player.play("fall")
			if from in GROUND_STATES:   # 从地面状态转换时启动土狼计时器
				coyote_timer.start()
			fall_from_y = global_position.y
		
		State.LANDING:
			if from != State.LANDING:   # 避免重复播放动画
				animation_player.play("landing")
		State.WALL_SLIDING:
			animation_player.play("wall_sliding")
		
		State.WALL_JUMP:
			animation_player.play("jump")
			velocity = WALL_JUMP_VELOCITY  # 设置墙面跳跃速度
			velocity.x *= get_wall_normal().x  # 根据墙面法线调整方向
			jump_request_timer.stop()          # 停止跳跃请求计时器
		
		State.ATTACK_1:
			animation_player.play("attack_1")
			is_combo_requested = false  # 重置连击请求
		State.ATTACK_2:
			animation_player.play("attack_2")
			is_combo_requested = false  # 重置连击请求
	
		State.ATTACK_3:
			animation_player.play("attack_3")
			is_combo_requested = false  # 重置连击请求
		State.HURT:
			animation_player.play("hurt")
			# 应用伤害
			stats.health -= pending_damage.amount
			# 计算击退方向
			var dir := pending_damage.source.global_position.direction_to(global_position)
			velocity = dir * KNOCKBACK_AMOUNT  # 应用击退
			pending_damage = null  # 清空待处理伤害
			invincible_timer.start()
			
		State.DYING:
			animation_player.play("die")
			invincible_timer.stop()
			interacting_with.clear()
	
		State.SLIDING_START:
			animation_player.play("sliding_start")
			slide_request_timer.stop()
			stats.energy -= SLIDING_ENERGY
			
		State.SLIDING_LOOP:
			animation_player.play("sliding_loop")
			
		State.SLIDING_END:
			animation_player.play("sliding_end")
			
	# 标记下一帧是状态的第一帧
	is_first_tick = true
	
# 受伤处理
func _on_hurtbox_hurt(hitbox: Hitbox) -> void:
	if invincible_timer.time_left > 0:
		return
	
	# 创建伤害对象
	pending_damage = Damage.new()
	pending_damage.amount = 1
	pending_damage.source = hitbox.owner
