draw_set_halign(fa_left);
draw_set_valign(fa_top);
draw_set_font(fnt_8);

if (!surface_exists(surf_battle_map)){
	draw_to_surface();
}

draw_surface(surf_battle_map, 0, 0);

draw_text(mouse_x, mouse_y, string(mouse_x div CELL_SIZE) + "," + string(mouse_y div CELL_SIZE));