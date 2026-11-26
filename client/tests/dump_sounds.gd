extends SceneTree
## Writes every table sound to WAV files so they can be listened to and
## measured outside the game:
##   godot --headless --path client --script res://tests/dump_sounds.gd -- <out_dir>


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("sounds")
	DirAccess.make_dir_recursive_absolute(out_dir)
	Sfx._build()
	for sound_name in Sfx._streams:
		var st = Sfx._streams[sound_name]
		var list: Array = st if st is Array else [st]
		for i in list.size():
			var path := out_dir.path_join("%s%s.wav" % [sound_name, "" if list.size() == 1 else "_%d" % i])
			list[i].save_to_wav(path)
			print(path)
	quit()
