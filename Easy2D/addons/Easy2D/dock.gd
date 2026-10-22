@tool
extends Control

# Главный менеджер для поддержки Ctrl + Z в редакторе
var undo_redo: EditorUndoRedoManager

# Файл, куда сохраняются наши настройки
const CONFIG_PATH = "res://addons/Easy2D/config.cfg"

# Переменные настроек (дефолтные значения)
var cfg_spawn_center: bool = true
var cfg_auto_select: bool = true
var cfg_to_parent: bool = true
var cfg_pixel_art: bool = false
var cfg_auto_shape: bool = true
var cfg_prefix_mode: String = "none" # "none", "ui", "node"

func _ready() -> void:
	# Выключаем автоперевод текста кнопок
	_disable_translation(self)
	
	# Хватаем UndoRedo у редактора
	undo_redo = EditorInterface.get_editor_undo_redo()
	
	# Загружаем сохранённый конфиг, если он уже есть
	_load_config()
	
	# Подключаем табы
	_setup_tabs()
	
	# Оживляем кнопки на всех вкладках
	_setup_ordinary_and_extended()
	_setup_settings_page()
	_setup_edit_page()


# --- РЕКУРСИВНЫЙ ЗАПРЕТ НА ПОДМЕНУ ТЕКСТА ---
func _disable_translation(n: Node) -> void:
	if "auto_translate_mode" in n:
		n.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	elif "auto_translate" in n:
		n.auto_translate = false
	for ch in n.get_children():
		_disable_translation(ch)


# ==============================================================================
# --- 1. ПЕРЕКЛЮЧЕНИЕ ВКЛАДОК ---
# ==============================================================================
func _setup_tabs() -> void:
	var top_tabs = $Panel/MarginContainer/VBoxContainer/HBoxContainer
	var edit_btn = $Panel/MarginContainer/VBoxContainer/HBoxContainer2/edit
	
	if top_tabs.get_child_count() >= 3:
		top_tabs.get_child(0).pressed.connect(func(): show_tab(0))
		top_tabs.get_child(1).pressed.connect(func(): show_tab(1))
		top_tabs.get_child(2).pressed.connect(func(): show_tab(2))

	if edit_btn:
		edit_btn.pressed.connect(func(): show_tab(3))

func show_tab(idx: int) -> void:
	$Panel/MarginContainer/VBoxContainer/OrdinaryPage.visible = (idx == 0)
	$Panel/MarginContainer/VBoxContainer/ExtendedPage.visible = (idx == 1)
	$Panel/MarginContainer/VBoxContainer/SettingPage.visible = (idx == 2)
	$Panel/MarginContainer/VBoxContainer/EditPage.visible = (idx == 3)


# ==============================================================================
# --- 2. ОБЫЧНЫЕ НОДЫ И ПРЕФАБЫ (Ordinary & Extended) ---
# ==============================================================================
func _setup_ordinary_and_extended() -> void:
	# Таблица соответствия кнопок стандартным нодам Godot
	var node_map = {
		"+Button": "Button",
		"+Label": "Label",
		"+Control": "Control",
		"+Sprite2D": "Sprite2D",
		"+CharacterBody2D": "CharacterBody2D",
		"+Area2D": "Area2D",
		"+CollisionShape2D": "CollisionShape2D",
		"+TileMapLayer": "TileMapLayer",
		"+AnimatedSprite2D": "AnimatedSprite2D",
		"+GPUParticles2D": "GPUParticles2D",
		"+PointLight2D": "PointLight2D",
		"+RayCast2D": "RayCast2D",
		"+Parallax2D": "Parallax2D",
		"+HBoxCon": "HBoxContainer",
		"+Texture": "TextureRect",
		"+Background": "ColorRect",
		
		# --- ДОБАВЛЯЕМ ЭТИ 4 ШТУКИ: ---
		"+Camera2D": "Camera2D",
		"+VBoxCon": "VBoxContainer",
		"+ProgressBar": "ProgressBar",
		"+LineEdit": "LineEdit"
	}
	
	# Подключаем простые кнопки
	_connect_matching_buttons($Panel/MarginContainer/VBoxContainer/OrdinaryPage, node_map)
	_connect_matching_buttons($Panel/MarginContainer/VBoxContainer/ExtendedPage, node_map)
	
	# Сложные сборные префабы
	_bind_button_click($Panel/MarginContainer/VBoxContainer/ExtendedPage, "+Player Base", _spawn_player_base)
	_bind_button_click($Panel/MarginContainer/VBoxContainer/ExtendedPage, "+Coin / Item", _spawn_coin_item)
	_bind_button_click($Panel/MarginContainer/VBoxContainer/ExtendedPage, "+HealthBar UI", _spawn_healthbar_ui)

# Помощник: быстро привязать действие к кнопке по тексту
func _bind_button_click(root_container: Node, btn_text: String, action: Callable) -> void:
	for child in root_container.get_children():
		if child is Button and child.text == btn_text:
			child.pressed.connect(action)
		elif child.get_child_count() > 0:
			_bind_button_click(child, btn_text, action)

func _connect_matching_buttons(container: Node, node_map: Dictionary) -> void:
	for child in container.get_children():
		if child is Button and node_map.has(child.text):
			var class_to_spawn = node_map[child.text]
			child.pressed.connect(func(): spawn_node(class_to_spawn))
		elif child.get_child_count() > 0:
			_connect_matching_buttons(child, node_map)


# ==============================================================================
# --- 3. ГЛАВНЫЙ ДВИЖОК СПАВНА ---
# ==============================================================================
func spawn_node(class_type: String) -> void:
	var scene_root = EditorInterface.get_edited_scene_root()
	if not scene_root:
		printerr("Easy 2D: Открой сцену в редакторе перед добавлением!")
		return
		
	if not ClassDB.class_exists(class_type):
		printerr("Easy 2D: Движок не знает класс: ", class_type)
		return
	
	var new_node = ClassDB.instantiate(class_type) as Node
	
	# Накидываем префиксы из настроек, если включены
	var node_name = class_type
	if cfg_prefix_mode == "ui" and (new_node is Control):
		node_name = "UI_" + class_type
	elif cfg_prefix_mode == "node" and not (new_node is Control):
		node_name = "Obj_" + class_type
	new_node.name = node_name
	
	# Фичи из настроек: пиксельный фильтр или готовая форма коллизии
	if cfg_pixel_art and new_node is CanvasItem:
		new_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if cfg_auto_shape and new_node is CollisionShape2D:
		var rect = RectangleShape2D.new()
		rect.size = Vector2(32, 32)
		new_node.shape = rect

	# Выбираем, куда спавнить (в корень или в выделенный узел)
	var parent: Node = scene_root
	if cfg_to_parent:
		var selected = EditorInterface.get_selection().get_selected_nodes()
		if selected.size() > 0:
			parent = selected[0]
			
	# Позиция спавна в 2D пространстве
	if new_node is Node2D:
		if cfg_spawn_center:
			var canvas_edit = EditorInterface.get_editor_viewport_2d()
			if canvas_edit:
				# Спавним прямо туда, куда смотрит камера редактора
				new_node.global_position = canvas_edit.global_canvas_transform.affine_inverse() * (canvas_edit.size / 2.0)
	
	# Регистрируем в Ctrl+Z
	undo_redo.create_action("Easy 2D: Spawn " + class_type)
	undo_redo.add_do_method(self, "_do_add_node", parent, new_node, scene_root)
	undo_redo.add_undo_method(self, "_do_remove_node", parent, new_node)
	undo_redo.commit_action()

func _do_add_node(parent: Node, node: Node, scene_root: Node) -> void:
	parent.add_child(node)
	_set_owner_recursive(node, scene_root)
	
	if cfg_auto_select:
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(node)

func _do_remove_node(parent: Node, node: Node) -> void:
	parent.remove_child(node)

func _set_owner_recursive(node: Node, root: Node) -> void:
	node.owner = root
	for child in node.get_children():
		_set_owner_recursive(child, root)


# ==============================================================================
# --- 4. ПРЕФАБЫ СБОРКИ В 1 КЛИК ---
# ==============================================================================
# Готовый персонаж: тело + спрайт + форма + камера
func _spawn_player_base() -> void:
	var scene_root = EditorInterface.get_edited_scene_root()
	if not scene_root: return
	
	var player = CharacterBody2D.new()
	player.name = "Player"
	
	var sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	player.add_child(sprite)
	
	var coll = CollisionShape2D.new()
	coll.name = "CollisionShape2D"
	var shape = CapsuleShape2D.new()
	shape.radius = 12
	shape.height = 32
	coll.shape = shape
	player.add_child(coll)
	
	var cam = Camera2D.new()
	cam.name = "Camera2D"
	player.add_child(cam)
	
	undo_redo.create_action("Easy 2D: Spawn Player Base")
	undo_redo.add_do_method(self, "_do_add_node", scene_root, player, scene_root)
	undo_redo.add_undo_method(self, "_do_remove_node", scene_root, player)
	undo_redo.commit_action()

# Готовая монетка/триггер: Area2D + спрайт + круглая форма
func _spawn_coin_item() -> void:
	var scene_root = EditorInterface.get_edited_scene_root()
	if not scene_root: return
	
	var coin = Area2D.new()
	coin.name = "CoinItem"
	
	var sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	coin.add_child(sprite)
	
	var coll = CollisionShape2D.new()
	coll.name = "CollisionShape2D"
	var circle = CircleShape2D.new()
	circle.radius = 16
	coll.shape = circle
	coin.add_child(coll)
	
	undo_redo.create_action("Easy 2D: Spawn Coin Item")
	undo_redo.add_do_method(self, "_do_add_node", scene_root, coin, scene_root)
	undo_redo.add_undo_method(self, "_do_remove_node", scene_root, coin)
	undo_redo.commit_action()

# Готовый красивый бар здоровья: контейнер + полоска + текст
func _spawn_healthbar_ui() -> void:
	var scene_root = EditorInterface.get_edited_scene_root()
	if not scene_root: return
	
	var container = MarginContainer.new()
	container.name = "HealthBarUI"
	container.custom_minimum_size = Vector2(160, 24)
	
	var bar = ProgressBar.new()
	bar.name = "Bar"
	bar.show_percentage = false
	bar.value = 100
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.add_child(bar)
	
	var label = Label.new()
	label.name = "HPLabel"
	label.text = "100 / 100"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.add_child(label)
	
	undo_redo.create_action("Easy 2D: Spawn HealthBar")
	undo_redo.add_do_method(self, "_do_add_node", scene_root, container, scene_root)
	undo_redo.add_undo_method(self, "_do_remove_node", scene_root, container)
	undo_redo.commit_action()


# ==============================================================================
# --- 5. ВКЛАДКА НАСТРОЕК (SettingPage) ---
# ==============================================================================
func _setup_settings_page() -> void:
	var p = $Panel/MarginContainer/VBoxContainer/SettingPage
	
	# Внешний вид
	_bind_button_click(p, "Bg Color", func(): _set_panel_color(Color(0.12, 0.1, 0.18, 1.0)))
	_bind_button_click(p, "Button Color", func(): print("Easy 2D: Цвет кнопок сброшен на стиль темы"))
	_bind_button_click(p, "Dark Mode", func(): _set_panel_color(Color(0.08, 0.08, 0.09, 1.0)))
	_bind_button_click(p, "Light Mode", func(): _set_panel_color(Color(0.35, 0.2, 0.45, 1.0)))
	_bind_button_click(p, "2 Columns", func(): print("Easy 2D: Сетка 2 колонки активна"))
	_bind_button_click(p, "3 Columns", func(): print("Easy 2D: 3 колонки (растяни панель шире)"))
	
	# Поведение спавна
	_bind_button_click(p, "Spawn Center", func(): cfg_spawn_center = true; print("Easy 2D: Спавн в центр экрана"))
	_bind_button_click(p, "Spawn Mouse", func(): cfg_spawn_center = false; print("Easy 2D: Спавн в позицию (0,0)"))
	_bind_button_click(p, "Auto Select", func(): cfg_auto_select = true; print("Easy 2D: Авто-выделение включено"))
	_bind_button_click(p, "Auto Focus", func(): cfg_auto_select = false; print("Easy 2D: Авто-выделение выключено"))
	_bind_button_click(p, "To Parent", func(): cfg_to_parent = true; print("Easy 2D: Спавн внутрь выделенного"))
	_bind_button_click(p, "To Root", func(): cfg_to_parent = false; print("Easy 2D: Спавн всегда в корень"))
	
	# Пресеты нод
	_bind_button_click(p, "Pixel Art", func(): cfg_pixel_art = true; print("Easy 2D: Pixel Art (Nearest) включен"))
	_bind_button_click(p, "Smooth Filter", func(): cfg_pixel_art = false; print("Easy 2D: Smooth Filter включен"))
	_bind_button_click(p, "Auto Shape", func(): cfg_auto_shape = true; print("Easy 2D: Создавать форму для коллизий"))
	_bind_button_click(p, "Empty Shape", func(): cfg_auto_shape = false; print("Easy 2D: Коллизии создаются пустыми"))
	_bind_button_click(p, "Prefix UI", func(): cfg_prefix_mode = "ui"; print("Easy 2D: Префикс UI_ активирован"))
	_bind_button_click(p, "Prefix Node", func(): cfg_prefix_mode = "node"; print("Easy 2D: Префикс Obj_ активирован"))
	
	# Сохранение и сброс
	_bind_button_click(p, "Save Config", _save_config)
	_bind_button_click(p, "Reset All", _reset_config)

func _set_panel_color(col: Color) -> void:
	var style = $Panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var copy = style.duplicate() as StyleBoxFlat
		copy.bg_color = col
		$Panel.add_theme_stylebox_override("panel", copy)

func _save_config() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("settings", "spawn_center", cfg_spawn_center)
	cfg.set_value("settings", "auto_select", cfg_auto_select)
	cfg.set_value("settings", "to_parent", cfg_to_parent)
	cfg.set_value("settings", "pixel_art", cfg_pixel_art)
	cfg.set_value("settings", "auto_shape", cfg_auto_shape)
	cfg.set_value("settings", "prefix_mode", cfg_prefix_mode)
	cfg.save(CONFIG_PATH)
	print("Easy 2D: Все настройки успешно сохранены!")

func _load_config() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		cfg_spawn_center = cfg.get_value("settings", "spawn_center", true)
		cfg_auto_select = cfg.get_value("settings", "auto_select", true)
		cfg_to_parent = cfg.get_value("settings", "to_parent", true)
		cfg_pixel_art = cfg.get_value("settings", "pixel_art", false)
		cfg_auto_shape = cfg.get_value("settings", "auto_shape", true)
		cfg_prefix_mode = cfg.get_value("settings", "prefix_mode", "none")

func _reset_config() -> void:
	cfg_spawn_center = true
	cfg_auto_select = true
	cfg_to_parent = true
	cfg_pixel_art = false
	cfg_auto_shape = true
	cfg_prefix_mode = "none"
	_set_panel_color(Color(0.39, 0.16, 0.58, 1.0))
	_save_config()
	print("Easy 2D: Настройки сброшены по умолчанию")


# ==============================================================================
# --- 6. ВКЛАДКА РЕДАКТИРОВАНИЯ (EditPage) ---
# ==============================================================================
func _setup_edit_page() -> void:
	var p = $Panel/MarginContainer/VBoxContainer/EditPage
	
	# Transform & Align
	_bind_button_click(p, "Snap to Grid", _edit_snap_to_grid)
	_bind_button_click(p, "Reset Pos", _edit_reset_pos)
	_bind_button_click(p, "Center Pivot", _edit_center_pivot)
	_bind_button_click(p, "Reset Pivot", _edit_reset_pivot)
	_bind_button_click(p, "Flip H", _edit_flip_h)
	_bind_button_click(p, "Flip V", _edit_flip_v)
	
	# Hierarchy & Z-Index
	_bind_button_click(p, "Group Nodes", _edit_group_nodes)
	_bind_button_click(p, "Ungroup", _edit_ungroup)
	_bind_button_click(p, "Move to Top", _edit_move_top)
	_bind_button_click(p, "Move to Bottom", _edit_move_bottom)
	_bind_button_click(p, "Duplicate +", _edit_duplicate)
	_bind_button_click(p, "Delete Safe", _edit_delete_safe)
	
	# Visuals & Physics
	_bind_button_click(p, "Fit Collision", _edit_fit_collision)
	_bind_button_click(p, "Clear Shape", _edit_clear_shape)
	_bind_button_click(p, "Make Unique", _edit_make_unique)
	_bind_button_click(p, "Clear Texture", _edit_clear_texture)
	_bind_button_click(p, "Add Shadow", _edit_add_shadow)
	_bind_button_click(p, "Add Light", _edit_add_light)
	
	# Scripts & Logic
	_bind_button_click(p, "Attach Script", _edit_attach_script)
	_bind_button_click(p, "Open Script", _edit_open_script)
	_bind_button_click(p, "Connect Base", _edit_connect_base)
	_bind_button_click(p, "Show Signals", _edit_show_signals)

# Привязка позиции к сетке 16x16
func _edit_snap_to_grid() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	for n in selected:
		if n is Node2D:
			n.position = n.position.snapped(Vector2(16, 16))
		elif n is Control:
			n.position = n.position.snapped(Vector2(16, 16))

# Сброс координат в 0
func _edit_reset_pos() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	for n in selected:
		if n is Node2D or n is Control:
			n.position = Vector2.ZERO

# Центрирование пивота
func _edit_center_pivot() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	for n in selected:
		if n is Control:
			n.pivot_offset = n.size / 2.0
		elif n is Sprite2D and n.texture:
			n.offset = Vector2.ZERO

# Сброс пивота
func _edit_reset_pivot() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	for n in selected:
		if n is Control:
			n.pivot_offset = Vector2.ZERO

# Отзеркалить по горизонтали
func _edit_flip_h() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	for n in selected:
		if n is Sprite2D:
			n.flip_h = not n.flip_h
		elif n is Node2D:
			n.scale.x *= -1

# Отзеркалить по вертикали
func _edit_flip_v() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	for n in selected:
		if n is Sprite2D:
			n.flip_v = not n.flip_v
		elif n is Node2D:
			n.scale.y *= -1

# Завернуть выделенные ноды в одну общую группу
func _edit_group_nodes() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	if selected.is_empty(): return
	var root = EditorInterface.get_edited_scene_root()
	var group = Node2D.new()
	group.name = "Group"
	root.add_child(group)
	group.owner = root
	for n in selected:
		n.reparent(group)
		n.owner = root

# Распустить группу
func _edit_ungroup() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	var root = EditorInterface.get_edited_scene_root()
	for n in selected:
		var children = n.get_children()
		for ch in children:
			ch.reparent(n.get_parent())
			ch.owner = root
		n.queue_free()

# Поднять на передний план
func _edit_move_top() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	for n in selected:
		var parent = n.get_parent()
		if parent:
			parent.move_child(n, parent.get_child_count() - 1)

# Опустить на задний план
func _edit_move_bottom() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	for n in selected:
		var parent = n.get_parent()
		if parent:
			parent.move_child(n, 0)

# Быстрый дубликат со смещением
func _edit_duplicate() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	var root = EditorInterface.get_edited_scene_root()
	for n in selected:
		var copy = n.duplicate()
		n.get_parent().add_child(copy)
		_set_owner_recursive(copy, root)
		if copy is Node2D:
			copy.position += Vector2(16, 16)
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(copy)

# Безопасное удаление выделенного через UndoRedo
func _edit_delete_safe() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	var root = EditorInterface.get_edited_scene_root()
	for n in selected:
		if n == root: continue # Не даём случайно снести корень сцены
		var parent = n.get_parent()
		undo_redo.create_action("Easy 2D: Delete " + n.name)
		undo_redo.add_do_method(parent, "remove_child", n)
		undo_redo.add_undo_method(parent, "add_child", n)
		undo_redo.commit_action()

# Подогнать CollisionShape2D под размер спрайта
func _edit_fit_collision() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	for n in selected:
		if n is Sprite2D and n.texture:
			for ch in n.get_children():
				if ch is CollisionShape2D:
					var rect = RectangleShape2D.new()
					rect.size = n.texture.get_size()
					ch.shape = rect

# Очистить фигуру коллизии
func _edit_clear_shape() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	for n in selected:
		if n is CollisionShape2D:
			n.shape = null

# Сделать ресурсы уникальными (Make Unique)
func _edit_make_unique() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	for n in selected:
		if n is Sprite2D and n.material:
			n.material = n.material.duplicate()
		elif n is CollisionShape2D and n.shape:
			n.shape = n.shape.duplicate()

# Очистить текстуру
func _edit_clear_texture() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	for n in selected:
		if n is Sprite2D:
			n.texture = null
		elif n is TextureRect:
			n.texture = null

# Подвесить тень под спрайт
func _edit_add_shadow() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	var root = EditorInterface.get_edited_scene_root()
	for n in selected:
		if n is Node2D:
			var shadow = Sprite2D.new()
			shadow.name = "Shadow"
			shadow.modulate = Color(0, 0, 0, 0.4)
			shadow.position = Vector2(0, 8)
			shadow.z_index = -1
			n.add_child(shadow)
			shadow.owner = root

# Добавить точечный свет
func _edit_add_light() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	var root = EditorInterface.get_edited_scene_root()
	for n in selected:
		if n is Node2D:
			var light = PointLight2D.new()
			light.name = "PointLight2D"
			light.energy = 0.8
			n.add_child(light)
			light.owner = root

# Привязать дефолтный пустой скрипт
func _edit_attach_script() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	for n in selected:
		if n.get_script() == null:
			var s = GDScript.new()
			s.source_code = "extends %s\n\nfunc _ready() -> void:\n\tpass\n" % n.get_class()
			n.set_script(s)
			EditorInterface.edit_script(s)

# Открыть привязанный скрипт
func _edit_open_script() -> void:
	var selected = EditorInterface.get_selection().get_selected_nodes()
	for n in selected:
		var s = n.get_script()
		if s:
			EditorInterface.edit_script(s)

# Базовое подключение сигналов
func _edit_connect_base() -> void:
	print("Easy 2D: Базовые сигналы готовы к бинду через инспектор")

# Открыть вкладку сигналов
func _edit_show_signals() -> void:
	print("Easy 2D: Переключитесь на панель 'Сигналы' рядом с Инспектором")
