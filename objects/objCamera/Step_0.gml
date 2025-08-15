cx = clamp(cx + (keyboard_check(ord("D")) - keyboard_check(ord("A")) ) * 16, 0, room_width - camera_get_view_width(view_camera[0]));
cy = clamp(cy + (keyboard_check(ord("S")) - keyboard_check(ord("W")) ) * 16, 0, room_height - camera_get_view_height(view_camera[0]));

camera_set_view_pos(view_camera[0], cx, cy);