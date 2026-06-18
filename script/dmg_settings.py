import os

app_path = defines["app"]
background_path = defines["background"]
app_name = defines.get("app_name", os.path.basename(app_path))

format = defines.get("image_format", "UDZO")
filesystem = "HFS+"
files = [(app_path, app_name)]
symlinks = {"Applications": "/Applications"}
background = background_path
window_rect = ((100, 100), (720, 440))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 13
icon_size = 128
icon_locations = {
    app_name: (180, 245),
    "Applications": (540, 245),
}
hide_extensions = [app_name]
