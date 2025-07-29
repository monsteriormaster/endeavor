extends Node
class_name cardInfos
var file_path = "res://components/Card_ui/assets/cardinfos.csv"
var infosDic:Dictionary

func _init() -> void:
	infosDic=read_csv_as_nested_dict(file_path)
	#函数读取csv文件并转换未嵌套字典，用于将管理整个卡牌系统
	
func read_csv_as_nested_dict(path: String) -> Dictionary:
	var data = {}
	var file = FileAccess.open(path,FileAccess.READ)
	var headers = []
	var first_line = true
	while not file.eof_reached():
		var values = file.get_csv_line()
		if first_line:
			headers = values
			first_line = false
		elif values.size()>=2:
			var key = values[0]
			var row_dict = {}
			for i in range(0,headers.size()):
				row_dict[headers[i]] = values[i]
			data[key] = row_dict
	file.close()
	return data
