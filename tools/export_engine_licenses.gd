extends SceneTree


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size()!=1: quit(1); return
	var directory: String=arguments[0]
	DirAccess.make_dir_recursive_absolute(directory)
	var license := FileAccess.open(directory.path_join("ENGINE_LICENSE.txt"),FileAccess.WRITE)
	license.store_string(Engine.get_license_text())
	license.close()
	var notices := FileAccess.open(directory.path_join("THIRD_PARTY_NOTICES.json"),FileAccess.WRITE)
	notices.store_string(JSON.stringify(Engine.get_copyright_info(),"  "))
	notices.close()
	var licenses := FileAccess.open(directory.path_join("THIRD_PARTY_LICENSES.json"),FileAccess.WRITE)
	licenses.store_string(JSON.stringify(Engine.get_license_info(),"  "))
	licenses.close()
	print("Engine licence export complete")
	quit()
