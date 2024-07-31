# <img src="Media/Icon.png" width="64" height="64"> Godot Ref Serializer

Helper class to serialize and deserialize light-weight RefCounted objects in Godot Engine.

## But why

Godot currently lacks struct support. The only available serializable data type are Resources (and _technically_ nodes, but they are stored as PackedScene Resource). While they allow you to pass data, serialize it and store, they come with unnecessary bloat. All Resources are stored in a global cache and custom resources can't be saved without referencing their original script, making the files verbose.

Example Item resource with a single `value` property:
```
[gd_resource type="Resource" script_class="Item" load_steps=2 format=3 uid="uid://2my71aus6ewg"]

[ext_resource type="Script" path="res://TestProject/CustomResource.gd" id="1_vcbgm"]

[resource]
script = ExtResource("1_vcbgm")
value = 5
```

RefSerializer provides an alternative for storing data - you can use simple RefCounted objects. They are lighter than Resources and store in a compact format.

The same Item stored as RefCounted:
```
{
"$type": &"Item",
"value": 5
}
```

Notice how it doesn't reference any script, only storing a type. It's nice and compact, but comes with some caveats explained below.

## How does it work

RefCounted objects can't be serialized normally. RefSerializer has a custom serialization code that makes it possible. But it doesn't work on just any RefCounted object - you need to register them. The way registration works gives some nice possibilities.

To register a class, you need to provide its name and a constructor, e.g.
```GDScript
RefSeriRefSerializer.register_type(&"Item", Item.new)
```
The constructor is a Callable that returns RefCounted object. It can be `new()` method of a class or a custom method. This means that you can register any class - it can be an internal class or a class defined in built-in script. You can also register a factory method that returns a pre-configured object. Since the registered class is not bound to any file, moving the class' script will not break any stored objects, because they always know how to load.

The caveat is that you need to use a special method to create registered objects:
```GDScript
var item: Item = RefSerializer.create_object(&"Item")
```
This is because the object needs to know its type and RefSerializer ensures it using `set_meta()`. However, since `create_object()` returns RefCounted, this code results in unsafe lines. If you are type purist then it's a major issue compared to regular classes that allow `var object := Item.new()` in a fully type-safe way.

Serialization only works with registered RefCounted objects. Non-registered RefCounted (i.e. created outside `create_object()`), Resources, or Nodes can't be serialized. This makes the usage limited to very simple struct-like types. Also you can't edit RefCounted objects in the inspector.

## Usage

First define a class. It has to extend RefCounted, but this type is implicit, so you can just do:
```GDScript
class Item:
    var value: int
```
Then, as mentioned above, it needs to be registered:
```GDScript
RefSerializer.register_type(&"Item", Item.new)
```
And finally, you instance the object like this:
```GDScript
var item: Item = RefSerializer.create_object(&"Item")
```
You can serialize the object using:
```GDScript
var data := RefSerializer.serialize_object(item)
```
This method returns a Dictionary that represents the object. It contains `$type` field that holds the object's type and a key for each object's property. Note that RefCounted does not support `@export` annotation, so it just stores all defined properties.

Serialization is recursive. If your RefCounted has another RefCounted in a variable, including inside Array or a Dictionary, it will be serialized too.

Deserialization is as easy:
```GDScript
var item: Item = RefSerializer.deserialize_object(data)
```

The data Dictionary can be stored on disk manually or using file methods of RefSerializer. They store the objects directly in a file, either text or binary.

```GDScript
RefSerializer.save_as_text(item, "res://Items/Item001.dat")
var item: Item = RefSerializer.load_from_text("res://Items/Item001.dat")
```

Note that file methods don't have any safeguards. If a file does not exist or has invalid data, it will result in a hard error.

## Customization

RefSerializer has a couple of static properties that affect the serializing behavior. It is recommended to set them before any usage of the class and never change them again. Example customization: `RefSerializer.serialize_defaults = false`.

-  `serialize_defaults` *(default: true)*: If disabled, properties that are equal to their default value (determined when the object is created) will not be serialized. This option saves storage size at a minor cost of performance.

- `skip_underscore_properties` *(default: false)*: If enabled, properties that start with underscore (`_`) will not be serialized. This is useful for redundant/temporary properties or properties that can't be serialized (e.g. Objects).

- `send_deserialized_notification` *(default: true)*: If enabled, when an object is deseralized and after its properties are loaded, it will receive a custom `NOTIFICATION_DESERIALIZED`. If you have helper properties that aren't stored, you can use it to initialize them.

### Notification usage example

Consider a World class with a Dictionary where key is position and value is a Room object. Room is defined like this:
```GDScript
class Room:
    var _position: Vector2
    var size: Vector2
```
It has a helper property `_position`, which is useful to know the position with only Room reference. But since the position is also a key in the Dictionary, there is no reason to store it.
Room instances are created like this:
```GDScript
var room: Room = RefSerializer.create_object(&"Room")
room._position = some_vector
room_list[some_vector] = room
```
The `_position` is initialized with the object, but since it's not saved, we have to restore it when loading. This is when notification can be used:
```GDScript
class World:
    var room_list: Dictionary

    func _notification(what: int):
        if what == RefSerializer.NOTIFICATION_DESERIALIZED:
            for pos in room_list:
                room_list[pos]._position = pos
```

## Closing notes

Serializable RefCounted objects come with some limitations, but they are the closest thing to a typed light-weight structs (passed by reference). Whether they are useful to you depends on your workflow.

When to use RefSerializer:
- You need some light-weight data type to pass around.
- Your data doesn't use Resources or Nodes.
- You have a custom editor for that data.
- You want a storage type that won't break when you move a script (especially relevant for save data, which isn't stored inside the project).
- You want to serialize internal classes (i.e. `class` instead of `class_name`).
- You want a compact storage format.

When to use Resource:
- You need data that use built-in Resources (textures, audio streams etc.).
- You need Resource cache (i.e. load Resource anywhere to obtain the same instance).
- You want your code to be fully type-safe.
- You want your data to be editable in the inspector.

___
You can find all my addons on my [profile page](https://github.com/KoBeWi).

<a href='https://ko-fi.com/W7W7AD4W4' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://cdn.ko-fi.com/cdn/kofi1.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>
