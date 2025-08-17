if (!surface_exists(surf_hpa)){
	surf_hpa = surface_create(room_width, room_height);	
	
	surface_set_target(surf_hpa);
	
	draw_set_alpha(0.75);
	
	//show_debug_message("global.hpa_clusters_by_level: " + string(global.hpa_clusters_by_level))
	
	var _cluster_pixel_wh = CLUSTER_SIZE * TILE_SIZE_PIXELS
	
	for (var i = 0; i < array_length(global.hpa_clusters_by_level[0]); i ++){
		var _data = global.hpa_clusters_by_level[0][i];
		var _abstract_node_indexes = _data.abstract_nodes;
		var _cluster_grid_x = _data.cluster_grid_x * _cluster_pixel_wh;
		var _cluster_grid_y = _data.cluster_grid_y * _cluster_pixel_wh;
		
		draw_set_colour(c_red);
		
		draw_rectangle(_cluster_grid_x, 
					   _cluster_grid_y, 
					   _cluster_grid_x + _cluster_pixel_wh, 
					   _cluster_grid_y + _cluster_pixel_wh,
					   true)
		
		
		draw_set_colour(c_lime);
		
		for (var _abstract_array_index = 0; _abstract_array_index < array_length(_abstract_node_indexes); _abstract_array_index ++){
			var _abstract_node_index = _abstract_node_indexes[_abstract_array_index];
			var _abstract_node = global.hpa_all_abstract_nodes[_abstract_node_index];
	
			draw_rectangle(_abstract_node.x, _abstract_node.y, _abstract_node.x + TILE_SIZE_PIXELS, _abstract_node.y + TILE_SIZE_PIXELS, false);
		}
		
		var _intra_edges = _data.intra_edges;
		
		draw_set_colour(c_aqua);
		
		for (var j = 0; j < array_length(_intra_edges); j ++){
			var _intra_edge = _intra_edges[j];
			var _from_node_id = global.hpa_all_abstract_nodes[_intra_edge.from_node_id];
			var _to_node_id = global.hpa_all_abstract_nodes[_intra_edge.to_node_id];
			
			draw_line(_from_node_id.x, _from_node_id.y, _to_node_id.x, _to_node_id.y);	
		}
	}
	
	draw_set_alpha(1);
	surface_reset_target();
}

draw_surface(surf_hpa, 0, 0);

//var _cluster = get_cluster_for_tile(mouse_x div CLUSTER_SIZE, mouse_y div CLUSTER_SIZE, 0);
////show_debug_message("_cluster: " + string(_cluster));
//draw_set_halign(fa_right);
//draw_set_valign(fa_top);
//draw_text(mouse_x, mouse_y, string(_cluster.cluster_id));

if (state == 2){
	//found: (array_length(_tile_path) > 0), tile_path: _tile_path
	//show_debug_message("result: " + string(result))
	for (var i = 0; i < array_length(result.tile_path); i ++){
		draw_circle(result.tile_path[i].x * TILE_SIZE_PIXELS, result.tile_path[i].y * TILE_SIZE_PIXELS, 5, true); 	
	}
}