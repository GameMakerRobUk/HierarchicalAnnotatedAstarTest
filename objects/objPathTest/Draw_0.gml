draw_set_halign(fa_left);
draw_set_valign(fa_top);
draw_set_font(fnt_8);

if (things_to_show != e_things_to_show.clearance_only){
	draw_set_alpha(0.5);

	for (var i = 0; i < array_length(hierarchy_nodes[current_hierarchy_level].entrance_nodes); i ++){
		var _node = hierarchy_nodes[current_hierarchy_level].entrance_nodes[i];
		draw_set_colour(c_lime);
		draw_circle(_node.x + (CELL_SIZE/2), _node.y + (CELL_SIZE/2), (CELL_SIZE/4), false);
	}

	draw_set_alpha(1);
}

if (things_to_show != e_things_to_show.entrances_only){
	draw_set_colour(c_white);

	for (var yy = 0; yy < VCELLS; yy ++){
		for (var xx = 0; xx < HCELLS; xx ++){
		
			var _node = all_nodes[xx][yy];
		
			var _clearance = _node.hierarchy_data[current_hierarchy_level].clearance;
			draw_text(xx * CELL_SIZE, yy * CELL_SIZE, string(_clearance));
		}	
	}
}

var _nodes_per_cluster = hierarchy_nodes[current_hierarchy_level].nodes_per_cluster;
draw_set_colour(c_blue);

for (var yy = 0; yy < ceil(VCELLS div _nodes_per_cluster); yy ++){
	for (var xx = 0; xx < ceil(HCELLS div _nodes_per_cluster); xx ++){
		
		var _x1 = xx * CELL_SIZE * _nodes_per_cluster;
		var _y1 = yy * CELL_SIZE * _nodes_per_cluster;
		var _x2 = _x1 + (CELL_SIZE * _nodes_per_cluster);
		var _y2 = _y1 + (CELL_SIZE * _nodes_per_cluster)

		draw_line(_x1, _y1, _x2, _y1);
		draw_line(_x1, _y1, _x1, _y2);
	}
}

draw_text(mouse_x, mouse_y, string(mouse_x div CELL_SIZE) + "," + string(mouse_y div CELL_SIZE));