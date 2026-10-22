@tool
extends EditorPlugin

#Загружаем заранее сцену
const  DOCK_SCENE = preload("res://addons/Easy2D/dock.tscn")

#Переменная для хранения окна
var dock_inst: Control

#Включение плагина
func _enter_tree() -> void:
	#Создаём экземпляр сцены
	dock_inst = DOCK_SCENE.instantiate()
	
	#Добавляем панель в окно
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock_inst)
	
# При отключение плагина
func _exit_tree() -> void:
	# Удаляем панель
	if dock_inst:
		remove_control_from_docks(dock_inst)
		dock_inst.queue_free()
