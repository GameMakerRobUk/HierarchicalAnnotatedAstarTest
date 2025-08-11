draw_set_color(c_black);
var _gui_w = display_get_gui_width();
var _x1 = _gui_w - 40;

draw_rectangle(_x1, 0, _gui_w, 12, false);

draw_set_color(c_lime);
draw_set_halign(fa_left);
draw_set_valign(fa_top);

draw_text(_x1, 0, string(floor(fps_real)));