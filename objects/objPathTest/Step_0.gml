cx = clamp(cx + (keyboard_check(ord("D")) - keyboard_check(ord("A")) ) * CELL_SIZE, 0, room_width - camera_get_view_width(view_camera[0]));
cy = clamp(cy + (keyboard_check(ord("S")) - keyboard_check(ord("W")) ) * CELL_SIZE, 0, room_height - camera_get_view_height(view_camera[0]));

camera_set_view_pos(view_camera[0], cx, cy);


//Change Hierarchy level
if (keyboard_check_pressed(vk_up)) current_hierarchy_level ++;
if (keyboard_check_pressed(vk_down)) current_hierarchy_level --;

if (current_hierarchy_level < 0) current_hierarchy_level = hierarchy_levels - 1;
if (current_hierarchy_level >= hierarchy_levels) current_hierarchy_level = 0;

if (keyboard_check_pressed(vk_tab)) things_to_show ++;
if (things_to_show == e_things_to_show.last) things_to_show = 0;