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
						for (var _check_x = _start_x; _check_x <= _end_x; _check_x ++){
						    if (_check_x == _end_x || _check_y == _end_y){
								var _tile = tilemap_get(_map_id, _check_x, _check_y);
								if (_tile == 1){
									_check_y = _end_y + 1;
									_check_x = _end_x + 1;
								}else{
									if (_check_x == _end_x && _check_y == _end_y){
										_size ++;
										if (_size < _nodes_per_cluster){
											_end_x ++;
											_end_y ++;
										}
									}
								}
							}
						}
					}
					
					all_nodes[_node_xx][_node_yy].hierarchy_data[_level].clearance = _size;
					
					//Add possible entrance nodes to be checked later
					if ( (_node_xx != HCELLS - 1 && _node_xx == (xx + _nodes_per_cluster - 1)) || 
					     (_node_yy != VCELLS - 1 && _node_yy == (yy + _nodes_per_cluster - 1)) || 
						 (xx != 0 &&_node_xx == xx) || 
						 (yy != 0 &&_node_yy == yy) ){
							 
						var _node = all_nodes[_node_xx][_node_yy];
						array_push(_current_level.entrance_nodes, _node);
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
/*

all_nodes = [];

for (var yy = 0; yy < ceil(VCELLS div 5); yy ++){
	for (var xx = 0; xx < ceil(HCELLS div 5); xx ++){
		nodes_size_five[xx][yy] = {cell_x : xx, cell_y : yy, x : xx * CELL_SIZE * 5, y : yy * CELL_SIZE * 5}
	}	
}

for (var yy = 0; yy < ceil(VCELLS / 10); yy ++){
	for (var xx = 0; xx < ceil(HCELLS / 10); xx ++){
		nodes_size_ten[xx][yy] = {cell_x : xx, cell_y : yy, x : xx * CELL_SIZE * 10, y : yy * CELL_SIZE * 10}
	}	
}

var _lay_id = layer_get_id("Tiles_1");
var _map_id = layer_tilemap_get_id(_lay_id);

for (var yy = 0; yy < VCELLS; yy ++){
	for (var xx = 0; xx < HCELLS; xx ++){
		//Calculate Clearance
		var _size = 0;
		
		var _start_x = xx;
		var _start_y = yy;
		var _end_x = xx;
		var _end_y = yy;
			
		for (var _check_y = _start_y; _check_y <= _end_y; _check_y ++){
			for (var _check_x = _start_x; _check_x <= _end_x; _check_x ++){
			    if (_check_x == _end_x || _check_y == _end_y){
					var _tile = tilemap_get(_map_id, _check_x, _check_y);
					if (_tile == 1){
						_check_y = _end_y + 1;
						_check_x = _end_x + 1;
					}else{
						if (_check_x == _end_x && _check_y == _end_y){
							_size ++;
							if (_size < 5){
								_end_x ++;
								_end_y ++;
							}
						}
					}
				}
			}
		}
		all_nodes[xx][yy] = _size;
	}	
}

window_set_fullscreen(true);

cx = 0;
cy = 0;