#macro CELL_SIZE 8
#macro HCELLS room_width div CELL_SIZE
#macro VCELLS room_height div CELL_SIZE


hierarchy_levels = 3;
var _nodes_per_cluster = 5;
all_nodes = [];
hierarchy_nodes = [];

var _lay_id = layer_get_id("Tiles_1");
var _map_id = layer_tilemap_get_id(_lay_id);

//Create Nodes
for (var yy = 0; yy < VCELLS; yy ++){
	for (var xx = 0; xx < HCELLS; xx ++){
		all_nodes[xx][yy] = {cell_x : xx, cell_y : yy, x : xx * CELL_SIZE, y : yy * CELL_SIZE, hierarchy_data : [{clearance : 0, is_entrance : false}, {clearance : 0, is_entrance : false} ,{clearance : 0, is_entrance : false} ]}
	}	
}
for (var _level = 0; _level < hierarchy_levels; _level ++){
	
	var _current_level = {nodes_per_cluster : _nodes_per_cluster, nodes : [], entrance_nodes : []};
	
	for (var yy = 0; yy < VCELLS; yy += _nodes_per_cluster){
		for (var xx = 0; xx < HCELLS; xx += _nodes_per_cluster){
			_current_level.nodes[xx div _nodes_per_cluster][yy div _nodes_per_cluster] =  {cell_x : xx, cell_y : yy, x : xx * CELL_SIZE, y : yy * CELL_SIZE}
			
			#region Calculate clearance for this cluster
			
			for (var _node_yy = yy; _node_yy < yy + _nodes_per_cluster; _node_yy ++){
				for (var _node_xx = xx; _node_xx < xx + _nodes_per_cluster; _node_xx ++){
					var _size = 0;
		
					var _start_x = _node_xx;
					var _start_y = _node_yy;
					var _end_x = _node_xx;
					var _end_y = _node_yy;
			
					for (var _check_y = _start_y; _check_y <= _end_y; _check_y ++){
						for (var _check_x = _check_y = _end_y ? _start_x : _end_x; _check_x <= _end_x; _check_x ++){
						    if (_check_x == _end_x || _check_y == _end_y){
								var _tile = tilemap_get(_map_id, _check_x, _check_y); 
								if (_node_xx == 39 && _node_yy == 40){
									show_debug_message("_check_x: " + string(_check_x) + " | _check_y: " + string(_check_y) + " _tile: " + string(_tile))	
								}
								
								if (_tile == 1){
									_check_y = _end_y + 1;
									_check_x = _end_x + 1;
									show_debug_message("Level: " + string(_level) + " | _size: " + string(_size) + " | _node x/y: " + string(_node_xx) + "," + string(_node_yy));
								}else{
									if (_check_x == _end_x && _check_y == _end_y){
										_size ++;
										if (_size < _nodes_per_cluster){
											_end_x ++;
											_end_y ++;
											if (_end_x * CELL_SIZE >= room_width || _end_y * CELL_SIZE >= room_height){
												_check_y = _end_y + 1;
												_check_x = _end_x + 1;
											}else{
												_check_x = _start_x;
												_check_y = _start_y;
											}
										}
									}
								}
							}
						}
					}
					
					all_nodes[_node_xx][_node_yy].hierarchy_data[_level].clearance = _size; show_debug_message("all_nodes[_node_xx][_node_yy].hierarchy_data[_level].clearance: " + string(all_nodes[_node_xx][_node_yy].hierarchy_data[_level].clearance))
					
					//Add possible entrance nodes to be checked later
					if ( (tilemap_get(_map_id, _node_xx, _node_yy) != 1) && ( 
					     (_node_xx != HCELLS - 1 && _node_xx == (xx + _nodes_per_cluster - 1)) || 
					     (_node_yy != VCELLS - 1 && _node_yy == (yy + _nodes_per_cluster - 1)) || 
						 (xx != 0 &&_node_xx == xx) || 
						 (yy != 0 &&_node_yy == yy) )){
						
						//is there a partner node on the other side? - should add the paired node at the same time - will halve the calculations
						if (_node_xx == (xx + _nodes_per_cluster - 1) && tilemap_get(_map_id, _node_xx + 1, _node_yy) != 1) || (_node_yy == (yy + _nodes_per_cluster - 1) && tilemap_get(_map_id, _node_xx, _node_yy + 1) != 1)
						|| ((xx != 0 &&_node_xx == xx) && tilemap_get(_map_id, _node_xx - 1, _node_yy) != 1) || ((yy != 0 &&_node_yy == yy) && tilemap_get(_map_id, _node_xx, _node_yy - 1) != 1){
							var _node = all_nodes[_node_xx][_node_yy];
							array_push(_current_level.entrance_nodes, _node);
						}
					}
				}
			}
			
			#endregion
		}	
	}
	
	hierarchy_nodes[_level] = _current_level;
	_nodes_per_cluster *= 2;
}
//show_debug_message("hierarchy_nodes: " + string(hierarchy_nodes))
window_set_fullscreen(true);

cx = 0;
cy = 0;
current_hierarchy_level = 0;

enum e_things_to_show {entrances_and_clearance, entrances_only, clearance_only, last}
things_to_show = e_things_to_show.entrances_and_clearance;