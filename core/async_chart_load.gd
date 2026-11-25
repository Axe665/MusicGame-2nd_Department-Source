extends RefCounted

## 把单谱 JSON 的解析与 Chart 构建放到 WorkerThreadPool，主线程只轮询。
## 一次只跑一个任务：调用方（main.gd）用一个变量持有它。
## 工程集 / 三文件谱 / .lbp 不走这里，它们还带素材复制。

var path: String = ""
var chart: Chart = null
var error: String = ""

var _task: int = -1


func begin(p: String) -> bool:
	path = p
	chart = null
	error = ""
	ChartIO.parse_done = 0
	ChartIO.parse_total = 0
	_task = WorkerThreadPool.add_task(_run, false, "chart parse")
	return true


## 0 = 还在跑，1 = 成功，2 = 失败。
func poll() -> int:
	if _task < 0:
		return 2
	if not WorkerThreadPool.is_task_completed(_task):
		return 0
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	return 1 if chart != null else 2


func _run() -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "无法读取：%s" % path
		return
	var text := file.get_as_text()
	file.close()
	var parsed := ChartIO.from_json(text)
	if parsed == null:
		error = ChartIO.last_error
		return
	# 和同步 load_chart 保持一致：单文件谱不挂工程目录。
	parsed.project_dir = ""
	parsed.project_main_path = ""
	chart = parsed
