tool
extends "res://addons/scene_notes/dock.gd"

const DOCK_NAME = "Scene Notes"
const SceneNotesDock = preload("res://addons/scene_notes/Scene Notes.tscn")
const AboutDialog = preload("res://addons/scene_notes/About.tscn")

const TAGS = ["TODO", "HACK", "FIXME", "BUG", "NOTE"]

var current_scene = null
var notes = null
var about
var more
var last_syntax_highlight = 0

func _init() . (SceneNotesDock):
	pass

func get_plugin_name():
  return DOCK_NAME

func get_plugin_icon():
  return load(get_addon_dir() + "icon.png")

func setup_dock(dock):
	dock.name = DOCK_NAME
	
	var editor = dock.get_node("Content/Editor")
	
	# manual overrides to prevent godot from highlighting text as it would code
	editor.add_color_override("font_color", get_syntax_color("text_color"))
	editor.add_color_override("function_color", get_syntax_color("text_color"))
	editor.add_color_override("member_variable_color", get_syntax_color("text_color"))
	editor.add_color_override("symbol_color", get_syntax_color("text_color"))
	editor.add_color_override("number_color", get_syntax_color("text_color"))
	
	var icon = dock.get_node("Toolbars/Toolbar/Icon")
	icon.texture = get_icon("Node", "EditorIcons")
	
	about = AboutDialog.instance()
	about.get_node("MarginContainer/RichTextLabel").connect("meta_clicked", self, "open_link")
	get_editor_interface().get_editor_viewport().add_child(about)
	
	more = dock.get_node("Toolbars/Toolbar/More")
	more.icon = get_icon("arrow", "OptionButton")
	var popup = more.get_popup()
	popup.add_item("About")
	popup.connect("id_pressed", self, "menu_clicked")
	
	connect("scene_changed", self, "scene_changed")
	connect("scene_closed", self, "scene_closed")
	
	# track changes to the tree
	get_tree().connect("tree_changed", self, "add_syntax_highlights")
	
	notes = load_config("scene-notes.ini")
	
	scene_changed(get_edited_scene(), false)

# clean up before freeing the dock instance
func cleanup_dock(dock):
	if current_scene:
	  save_notes()
	
	save_config("scene-notes.ini", notes)
	
	notes = null
	disconnect("scene_changed", self, "scene_changed")
	disconnect("scene_closed", self, "scene_closed")
	more.get_popup().disconnect("id_pressed", self, "menu_clicked")
	about.get_node("MarginContainer/RichTextLabel").disconnect("meta_clicked", self, "open_link")
	get_editor_interface().get_editor_viewport().remove_child(about)
	# track changes to the tree
	get_tree().disconnect("tree_changed", self, "add_syntax_highlights")

func scene_changed(root, save_old = true):
	if save_old and current_scene:
		# gotta handle the old scene before opening a new one
		save_notes()
	
	# sometimes the editor will feed us an empty node out of the blue
	# but sometimes it's legit
	if ! root:
		display_empty()
		current_scene = null
		return
	
	# pretty up our interface with new scene info
	display_note(root)
	
	# update our state
	current_scene = root.filename
	load_notes()

# don't want to close a scene without saving its notes, now do we?
func scene_closed(path):
	if current_scene == path:
		save_notes()
		current_scene = null
	
	# if there's another scene tab, it'll open that one and overwrite this stuff
	# but just in case, to be pretty, we display an "empty" scene and disable editing
	display_empty()
	
	var editor = instance.get_node("Content/Editor")
	editor.text = ""
	editor.readonly = true

func display_note(root):
	instance.get_node("Toolbars/Toolbar/Scene").text = root.filename.split("/")[-1]
	instance.get_node("Toolbars/Toolbar/Icon").texture = get_icon(root.get_class(), "EditorIcons")
	instance.get_node("Content/Editor").readonly = false
	add_syntax_highlights(true)

func display_empty():
	instance.get_node("Toolbars/Toolbar/Scene").text = "[empty]"
	instance.get_node("Toolbars/Toolbar/Icon").texture = get_icon("Node", "EditorIcons")
	instance.get_node("Content/Editor").readonly = true
	instance.get_node("Content/Editor").text = ""

# BUG: when a new (blank) scene is created, no signal is emitted
# so there's no way to display the [empty] note for new scene creation
# the `SceneTree.tree_changed` event should probably fire but it doesn't

# resets the syntax highlighting and adds some of our own
func add_syntax_highlights(force = false):
	# maximum of 15 fps
	if ! force or OS.get_ticks_msec() - last_syntax_highlight < 64:
		return
	
	last_syntax_highlight = OS.get_ticks_msec()
	
	var root = get_edited_scene()
	
	if !root:
		return
	
	var editor = instance.get_node("Content/Editor")
	editor.clear_colors()
	
	if root is Node:
		add_tree_highlights(root, editor, get_syntax_color("gdscript/node_path_color"))
	
	for tag in TAGS:
		editor.add_keyword_color(tag, get_syntax_color("keyword_color"))
	
	for cls in ClassDB.get_class_list():
		editor.add_keyword_color(cls, get_syntax_color("keyword_color"))

# traverses the tree recursively, highlighting node names as we go
func add_tree_highlights(root, editor, color):
	# if there's a space in the name, highlight each individual word
	# hackish, but spaces break syntax highlighting otherwise
	if " " in root.name:
		for word in root.name.split(" "):
			editor.add_keyword_color(word, color)
	else:
		editor.add_keyword_color(root.name, color)
	
	if root.get_child_count():
		for node in root.get_children():
			add_tree_highlights(node, editor, color)

# load and display our notes from config
func load_notes():
	var note = notes.get_value(
		current_scene,
		"note",
		""
	)
	
	instance.get_node("Content/Editor").text = note

# save our notes to the config
func save_notes():
	if ! len(instance.get_node("Content/Editor").text):
		notes.erase_section(current_scene)
		return
	
	notes.set_value(
		current_scene,
		"note",
		instance.get_node("Content/Editor").text
	)	

func menu_clicked(id):
	# only one option right now :p
	about.popup_centered()

func open_link(url):
	OS.shell_open(url)

# shorthands because typing is work and i'm lazy
func get_edited_scene():
	return get_editor_interface().get_edited_scene_root()

func get_icon(name, group = ""):
	return get_editor_interface().get_base_control().get_icon(name, group)

func get_syntax_color(name):
	return get_editor_interface()\
		.get_editor_settings()\
		.get_setting("text_editor/highlighting/%s" % name)
