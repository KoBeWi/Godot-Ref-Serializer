class_name RefSerializer
## Utility class for registering and serializing light-weight RefCounted-based structs.
##
## RefSerializer allows you to register custom types based on [RefCounted], serialize them and store in files. The advantage of using RefCounted objects is that they are lighter than Resources and custom serialization allows for more compact storing. The types are not bound to any scripts, so there is no problems with compatibility.

## Notification received after deserializing object, if [member send_deserialized_notification] is enabled.
const NOTIFICATION_DESERIALIZED = 2137

## Dictionary key used to store object's type.
const TYPE_KEY = &"$type"

## Metadata name assigned to created RefCounted objects.
const TYPE_META = &"_type"

static var _types: Dictionary[StringName, Callable]
static var _default_cache: Dictionary[StringName, RefCounted]

## If [code]false[/code], properties with values equal to their defaults will not be serialized. This has a slight performance impact, but decreases storage size.
static var serialize_defaults: bool = false

## If [code]true[/code], properties that begin with underscore will not be serialized. This has a slight performance impact, but can be useful for redundant or temporary properties.
static var skip_underscore_properties: bool = false

## If [code]true[/code], deserialized object will receive [constant NOTIFICATION_DESERIALIZED], which can be used to initialize some values (e.g. properties skipped because of underscore).
static var send_deserialized_notification: bool = true

## Registers a custom type. You need to call this before creating or loading any instance of that type. [param constructor] can be any method that returns a [RefCounted] object, but it's most convenient to use [code]new[/code] method of a class.
## [codeblock]
## class Item:
##     var value: int
## 
## RefSerializer.register_type(&"Item", Item.new)
static func register_type(type: StringName, constructor: Callable):
	_types[type] = constructor
	
	if not serialize_defaults:
		_default_cache[type] = constructor.call()

## Creates a new instance of a registered [param type]. Only objects created using this method can be serialized.
## [codeblock]
## var item: Item = RefSerializer.create_object(&"Item")
static func create_object(type: StringName) -> RefCounted:
	var constructor = _types.get(type)
	if constructor is Callable:
		var object: RefCounted = constructor.call()
		object.set_meta(TYPE_META, type)
		return object
	
	assert(false, "Type not registered: %s" % type)
	return null

## Creates a new instance of [param object]'s type and copies all properties to the new object. The original object needs to have been created with [method create_object] or this method. If [param deep] is [code]true[/code], all [Array] and [Dictionary] properties will be recursively duplicated.
static func duplicate_object(object: RefCounted, deep := false) -> RefCounted:
	var type: StringName = object.get_meta(TYPE_META, &"")
	if type.is_empty():
		push_error("Object %s has no type info" % object)
		return null
	
	var duplicate := create_object(object.get_meta(TYPE_META))
	
	for property in object.get_property_list():
		if not property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		
		var property_string: String = property["name"]
		if skip_underscore_properties and property_string.begins_with("_"):
			continue
		
		var property_name: StringName = property_string
		var value: Variant = object.get(property_name)
		if deep:
			value = _duplicate_value(value)
		
		duplicate.set(property_name, value)
	
	return duplicate

static func _duplicate_value(value: Variant) -> Variant:
	if value is RefCounted:
		return duplicate_object(value)
	elif value is Object:
		assert(false, "Objects can't be serialized. Only registered RefCounteds are supported.")
		return null
	elif value is Array:
		var old_array := value as Array
		var new_array := Array([], old_array.get_typed_builtin(), old_array.get_typed_class_name(), old_array.get_typed_script())
		new_array.resize(old_array.size())
		
		for i in old_array.size():
			new_array[i] = _duplicate_value(old_array[i])
		return new_array
	elif value is Dictionary:
		var old_dictionary := value as Dictionary
		var new_dictionary := Dictionary({},
			old_dictionary.get_typed_key_builtin(), old_dictionary.get_typed_key_class_name(), old_dictionary.get_typed_key_script(),
			old_dictionary.get_typed_value_builtin(), old_dictionary.get_typed_value_class_name(), old_dictionary.get_typed_value_script())
		
		for key in old_dictionary:
			new_dictionary[key] = _duplicate_value(old_dictionary[key])
		return new_dictionary
	
	return value

## Serializes a registered object (created via [method create_object]) into a Dictionary, storing values of its properties. If a property value is equal to its default, it will not be stored unless [member serialize_defaults] is enabled. You can use [method deserialize_object] to re-create the object.
## [br][br]This method only supports [RefCounted] objects created with [method create_object]. The objects are serialized recursively if they are stored in any of the properties. If a property value is [Resource] or [Node], it will be serialized as [code]null[/code].
static func serialize_object(object: RefCounted) -> Dictionary[StringName, Variant]:
	var data: Dictionary[StringName, Variant]
	
	var type: StringName = object.get_meta(TYPE_META, &"")
	if type.is_empty():
		push_error("Object %s has no type info" % object)
		return data
	
	var default: RefCounted
	if not serialize_defaults:
		default = _default_cache.get(type)
	
	data[TYPE_KEY] = type
	for property in object.get_property_list():
		if not property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		
		var property_string: String = property["name"]
		if skip_underscore_properties and property_string.begins_with("_"):
			continue
		
		var property_name: StringName = property_string
		if default and value == default.get(property_name):
			continue
		
		data[property_name] = _serialize_value(value)
	
	return data

static func _serialize_value(value: Variant) -> Variant:
	if value is RefCounted:
		return serialize_object(value)
	elif value is Object:
		assert(false, "Objects can't be serialized. Only registered RefCounteds are supported.")
		return null
	elif value is Array:
		return value.map(func(element: Variant) -> Variant: return _serialize_value(element))
	elif value is Dictionary:
		var new_value: Dictionary
		for key in value:
			new_value[key] = _serialize_value(value[key])
		return new_value
	
	return value

## Deserializes a Dictionary created using [method serialize_object], returning an instance of its class. The Dictionary can be created manually, it just needs a [code]$type[/code] key with class name, other fields will be used to assign properties.
static func deserialize_object(data: Dictionary[StringName, Variant]) -> RefCounted:
	var type: StringName = data.get(TYPE_KEY, &"")
	if type.is_empty():
		push_error("Object data has no type info.")
		return null
	
	var object := create_object(type)
	for property in data:
		if property == TYPE_KEY:
			continue
		
		var value = _deserialize_value(data[property])
		if value is Array or value is Dictionary:
			object.get(property).assign(value)
		else:
			object.set(property, value)
	
	if send_deserialized_notification:
		object.notification(NOTIFICATION_DESERIALIZED)
	
	return object

static func _deserialize_value(value: Variant) -> Variant:
	if value is Dictionary:
		var type: StringName = value.get(TYPE_KEY, &"")
		if not type.is_empty():
			return deserialize_object(value)
		else:
			var new_value: Dictionary
			for key in value:
				new_value[key] = _deserialize_value(value[key])
			return new_value
	elif value is Array:
		return value.map(func(element: Variant) -> Variant: return _deserialize_value(element))
	
	return value

## Saves the registered object under the given path. The extension is irrelevant. The object is serialized before saving, using [method serialize_object], and stored in a text format with [method @GlobalScope.var_to_str].
static func save_as_text(object: RefCounted, path: String):
	var data := serialize_object(object)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(var_to_str(data))

## Saves the registered object under the given path. The extension is irrelevant. The object is serialized before saving, using [method serialize_object], and stored as a JSON string using [method JSON.from_native]. [param indent] specifies how the resulting JSON should be indented. You can pass empty [String] to disable indentation and save space.
static func save_as_json(object: RefCounted, path: String, indent := "\t"):
	var data := serialize_object(object)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(JSON.from_native(data), indent))

## Saves the registered object under the given path. The extension is irrelevant. The object is serialized before saving, using [method serialize_object], and stored in a binary format with [method FileAccess.store_var].
static func save_as_binary(object: RefCounted, path: String):
	var data := serialize_object(object)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(data)

## Loads and deserializes an object from a file saved in a text format. Only supports the format saved with [method save_as_text].
## [br][br][b]Note:[/b] As of now, the method [method @GlobalScope.str_to_var] used internally, allows for deserializing Objects and potentially arbitrary code execution, making it not suitable for save files. If you want to safely store the data as text, use [method save_as_json] and [method load_from_json] instead.
static func load_from_text(path: String) -> RefCounted:
	var data: Dictionary[StringName, Variant] = str_to_var(FileAccess.get_file_as_string(path))
	return deserialize_object(data)

## Loads and deserializes an object from a file saved as a JSON string. Only supports the format saved with [method save_as_json].
static func load_from_json(path: String) -> RefCounted:
	var data: Dictionary[StringName, Variant] = JSON.to_native(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return deserialize_object(data)

## Loads and deserializes an object from a file saved in a binary format. Only supports the format saved with [method save_as_binary].
static func load_from_binary(path: String) -> RefCounted:
	var file := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary[StringName, Variant] = file.get_var()
	return deserialize_object(data)
