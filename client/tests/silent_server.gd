extends SceneTree
## A server that accepts the connection and then never answers must not
## freeze the app. Before the fix, the Nakama client's threaded HTTPRequest
## timed out, the main thread waited on its stuck worker for ever, and the
## iPhone stopped drawing a few seconds into the lobby.
## Run: godot --headless --path client --script res://tests/silent_server.gd

## Frames must keep coming for this long while requests time out.
const RUN_MS := 12000
## A main-thread stall this long counts as a freeze.
const STALL_MS := 3000

var _server := TCPServer.new()
var _held: Array[StreamPeerTCP] = []
var _beat := 0
var _done := false
var _watchdog := Thread.new()
var _mutex := Mutex.new()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# Listens, takes every connection and reads nothing back to it.
	var port := 0
	for p in range(47350, 47400):
		if _server.listen(p, "127.0.0.1") == OK:
			port = p
			break
	if port == 0:
		print("SILENT SERVER FAILED: no free port")
		quit(1)
		return
	_set_beat()
	_watchdog.start(_watch)
	process_frame.connect(_on_frame)

	var net: Node = root.get_node("Net")
	net.host = "127.0.0.1"
	net.port = port
	net.scheme = "http"
	var start := Time.get_ticks_msec()
	# Two sign-ins in a row: each one waits out the request timeout.
	var ok: bool = await net.connect_to_server()
	if ok:
		_finish("SILENT SERVER FAILED: connected to a server that never answers", 1)
		return
	while Time.get_ticks_msec() - start < RUN_MS:
		await process_frame
	ok = await net.connect_to_server()
	if ok:
		_finish("SILENT SERVER FAILED: connected to a server that never answers", 1)
		return
	_finish("SILENT SERVER OK", 0)


func _on_frame() -> void:
	_set_beat()
	while _server.is_connection_available():
		_held.append(_server.take_connection())


func _set_beat() -> void:
	_mutex.lock()
	_beat = Time.get_ticks_msec()
	_mutex.unlock()


## Runs on its own thread: if the main thread stops ticking, says so and
## ends the process, since a frozen main thread can never quit by itself.
func _watch() -> void:
	while true:
		OS.delay_msec(250)
		_mutex.lock()
		var since := Time.get_ticks_msec() - _beat
		var done := _done
		_mutex.unlock()
		if done:
			return
		if since > STALL_MS:
			printerr("SILENT SERVER FAILED: the main thread froze for %d ms" % since)
			OS.kill(OS.get_process_id())
			return


func _finish(message: String, code: int) -> void:
	_mutex.lock()
	_done = true
	_mutex.unlock()
	_watchdog.wait_to_finish()
	for c in _held:
		c.disconnect_from_host()
	_server.stop()
	print(message)
	quit(code)
