extends RefCounted

## The card table accepts the default protocol's standard round contract.
static func party_definition() -> Dictionary:
	return {"dependencies": {}}


func check_request(request: Dictionary) -> Dictionary:
	if request.get("mode") != "standard":
		return {"ok": false, "code": "unsupported_mode", "message": "纸牌会客厅仅支持普通局"}
	return {"ok": true}


func make_config(request: Dictionary) -> Dictionary:
	return request.duplicate(true)


func map_result(result: Dictionary, _request: Dictionary) -> Dictionary:
	return result.duplicate(true)
