extends Resource
class_name ItemData
## One kind of item the player can carry. Each item is a .tres file in res://items/ whose file name
## matches its id (items/jar.tres has id "jar"). To make one in the editor: FileSystem dock,
## right-click items/ > Create New > Resource > ItemData.

## matches the file name; scripts use it to find the item (InventoryManager.get_item("jar"))
@export var id: String = ""
## what the hover label shows: capitals, and only the pixel font's characters
## (A-Z 0-9 . , ' - : ? ! ( ) / + = %)
@export var name: String = ""
## a 12x12 pixel-art icon from ui/ (made by pipeline/godot/make_ui_assets.py); without one the
## bar draws a "?" box
@export var icon: Texture2D
