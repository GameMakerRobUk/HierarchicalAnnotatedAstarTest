if (mouse_check_button_pressed(mb_left)){
	switch state{
		case 0 : {
			start_x = mouse_x div TILE_SIZE_PIXELS; 
			start_y = mouse_y div TILE_SIZE_PIXELS; 
			state = 1;
		}; break;
		case 1 : {
			result = hpa_find_path_tiles(start_x, start_y, mouse_x div TILE_SIZE_PIXELS, mouse_y div TILE_SIZE_PIXELS, 0); 
			state = 2;
		}; break;
		case 2 : {
			state = 0;	
		}
	}
}