// -----------------------------
// FULL HPA* IMPLEMENTATION (drop into a script or include)
// -----------------------------

#region Constants & Globals

/// adjust these two to match your project
#macro CLUSTER_SIZE            8          // tiles per cluster edge
#macro TILE_SIZE_PIXELS        8         // pixels per tile

#macro HCELLS                  (floor(room_width  / TILE_SIZE_PIXELS))
#macro VCELLS                  (floor(room_height / TILE_SIZE_PIXELS))

global.hpa_levels_total           = 1;
global.hpa_clusters_by_level      = [];   // [level][cluster_id] = cluster_struct
global.hpa_next_abstract_node_id  = 0;
global.hpa_all_abstract_nodes     = [];   // [node_id] = node_struct
global.hpa_inter_cluster_edges    = [];   // list of crossing edges (between clusters)

#endregion


#region Helpers (you can keep / tweak these)

/// Convert tile -> pixel top-left
function tile_to_pixel(_tile_x, _tile_y) {
    return { x: (_tile_x * TILE_SIZE_PIXELS), y: (_tile_y * TILE_SIZE_PIXELS) };
}

var _lay_id = layer_get_id("Tiles_1");
map_id = layer_tilemap_get_id(_lay_id);

function tile_is_walkable(_tile_x, _tile_y) {
    if ((_tile_x < 0) || (_tile_y < 0)) return false;
    if ((_tile_x >= HCELLS) || (_tile_y >= VCELLS)) return false;

    if (tilemap_get(map_id, _tile_x, _tile_y) != 0){
		show_debug_message("tile_is_walkable collision found");
		return false;
	}
    
    return true;
}

/// Small safe parser: convert "x,y" string -> {x,y}
function parse_tile_key(_key) {
    var _split = string_split(_key, ",");
    return { x: real(_split[0]), y: real(_split[1]) };
}

#endregion


#region Cluster construction (level 0)

/// get_cluster_bounds_in_tiles(cluster_grid_x, cluster_grid_y)
/// returns exclusive right/bottom bounds for safety
function get_cluster_bounds_in_tiles(_cluster_grid_x, _cluster_grid_y) {
    var _left_tile   = (_cluster_grid_x * CLUSTER_SIZE);
    var _top_tile    = (_cluster_grid_y * CLUSTER_SIZE);
    var _right_tile  = (_left_tile + CLUSTER_SIZE);  // exclusive
    var _bottom_tile = (_top_tile + CLUSTER_SIZE);   // exclusive

    return {
        left_tile:   _left_tile,
        top_tile:    _top_tile,
        right_tile:  _right_tile,
        bottom_tile: _bottom_tile
    };
}

/// Build clusters for a given level (0)
function build_clusters_for_level(_level_index) {
    var _clusters_for_level = [];
    var _clusters_across_x  = floor(HCELLS / CLUSTER_SIZE);
    var _clusters_down_y    = floor(VCELLS / CLUSTER_SIZE);

    for (var _cluster_grid_y = 0; _cluster_grid_y < _clusters_down_y; _cluster_grid_y++) {
        for (var _cluster_grid_x = 0; _cluster_grid_x < _clusters_across_x; _cluster_grid_x++) {
            var _cluster_id = ((_cluster_grid_y * _clusters_across_x) + _cluster_grid_x);
            var _bounds     = get_cluster_bounds_in_tiles(_cluster_grid_x, _cluster_grid_y);

            _clusters_for_level[_cluster_id] = {
                cluster_id:        _cluster_id,
                cluster_grid_x:    _cluster_grid_x,
                cluster_grid_y:    _cluster_grid_y,
                //tile_left:         _bounds.left_tile,
                //tile_top:          _bounds.top_tile,
				bounds : _bounds,
                abstract_nodes:    [],   // node IDs inside this cluster
                intra_edges:       []    // edges inside this cluster (node->node)
            };
			
			show_debug_message("cluster added [" + string(_cluster_id) + "]: " + string(_clusters_for_level[_cluster_id]))
        }
    }

    global.hpa_clusters_by_level[_level_index] = _clusters_for_level;
}

#endregion


#region Entrance detection & abstract nodes (inter-cluster edges)

// detect vertical entrance runs on a border column (inclusive y range)
function detect_vertical_entrance_runs(_border_tile_x, _tile_y_start_inclusive, _tile_y_end_inclusive) {
    var _entrance_runs = [];
    var _is_in_run     = false;
    var _run_start_y   = -1;

    for (var _tile_y = _tile_y_start_inclusive; _tile_y <= _tile_y_end_inclusive; _tile_y++) {
        var _left_walkable  = tile_is_walkable(_border_tile_x, _tile_y);
        var _right_walkable = tile_is_walkable((_border_tile_x + 1), _tile_y);
        var _can_cross_here = (_left_walkable && _right_walkable);

        if (_can_cross_here && !_is_in_run) { _is_in_run = true; _run_start_y = _tile_y; }
        if ((!_can_cross_here || (_tile_y == _tile_y_end_inclusive)) && _is_in_run) {
            var _run_end_y = (_can_cross_here ? _tile_y : (_tile_y - 1));
            array_push(_entrance_runs, [_run_start_y, _run_end_y]);
            _is_in_run = false;
        }
    }
    return _entrance_runs;
}

// detect horizontal entrance runs on a border row (inclusive x range)
function detect_horizontal_entrance_runs(_border_tile_y, _tile_x_start_inclusive, _tile_x_end_inclusive) {
    var _entrance_runs = [];
    var _is_in_run     = false;
    var _run_start_x   = -1;

    for (var _tile_x = _tile_x_start_inclusive; _tile_x <= _tile_x_end_inclusive; _tile_x++) {
        var _top_walkable    = tile_is_walkable(_tile_x, _border_tile_y);
        var _bottom_walkable = tile_is_walkable(_tile_x, (_border_tile_y + 1));
        var _can_cross_here  = (_top_walkable && _bottom_walkable);

        if (_can_cross_here && !_is_in_run) { _is_in_run = true; _run_start_x = _tile_x; }
        if ((!_can_cross_here || (_tile_x == _tile_x_end_inclusive)) && _is_in_run) {
            var _run_end_x = (_can_cross_here ? _tile_x : (_tile_x - 1));
            array_push(_entrance_runs, [_run_start_x, _run_end_x]);
            _is_in_run = false;
        }
    }
    return _entrance_runs;
}

/// Create an abstract node and attach to cluster
function create_abstract_node_for_cluster(_cluster_ref, _tile_x, _tile_y) {
    var _node_id = global.hpa_next_abstract_node_id;
    global.hpa_next_abstract_node_id++;

    var _pixel_pos = tile_to_pixel(_tile_x, _tile_y);

    var _node = {
        node_id:               _node_id,
        level_index:           0,
        owner_cluster_id:      _cluster_ref.cluster_id,
        owner_cluster_grid_x:  _cluster_ref.cluster_grid_x,
        owner_cluster_grid_y:  _cluster_ref.cluster_grid_y,
        tile_x:                _tile_x,
        tile_y:                _tile_y,
        x:                     _pixel_pos.x,
        y:                     _pixel_pos.y
    };

    global.hpa_all_abstract_nodes[_node_id] = _node;
    array_push(_cluster_ref.abstract_nodes, _node_id);
    return _node_id;
}

/// Build abstract nodes along shared borders and crossing edges (both directions)
function build_abstract_nodes_and_crossing_edges_for_level(_level_index) {
    var _clusters_array    = global.hpa_clusters_by_level[_level_index];
    var _clusters_across_x = floor(HCELLS / CLUSTER_SIZE);
    var _clusters_down_y   = floor(VCELLS / CLUSTER_SIZE);

    // vertical shared borders: left/right neighbors
    for (var _grid_y = 0; _grid_y < _clusters_down_y; _grid_y++) {
        for (var _grid_x = 0; _grid_x < (_clusters_across_x - 1); _grid_x++) {
            var _left_id  = ((_grid_y * _clusters_across_x) + _grid_x);
            var _right_id = (_left_id + 1);
            var _left_c   = _clusters_array[_left_id];
            var _right_c  = _clusters_array[_right_id];
            var _left_bounds = get_cluster_bounds_in_tiles(_left_c.cluster_grid_x, _left_c.cluster_grid_y);

            // shared border column is rightmost column of left cluster (inclusive)
            var _shared_border_tile_x = (_left_bounds.right_tile - 1);
            var _y_start_inclusive    = _left_bounds.top_tile;
            var _y_end_inclusive      = (_left_bounds.bottom_tile - 1);

            var _runs = detect_vertical_entrance_runs(_shared_border_tile_x, _y_start_inclusive, _y_end_inclusive);
            for (var _r = 0; _r < array_length(_runs); _r++) {
                var _run = _runs[_r];
                var _run_mid_y = ((_run[0] + _run[1]) >> 1);

                var _left_node_id  = create_abstract_node_for_cluster(_left_c,  _shared_border_tile_x,      _run_mid_y);
                var _right_node_id = create_abstract_node_for_cluster(_right_c, (_shared_border_tile_x + 1), _run_mid_y);

                array_push(global.hpa_inter_cluster_edges, {
                    from_node_id: _left_node_id, to_node_id: _right_node_id,
                    traversal_cost: 1, is_crossing_edge: true
                });
                array_push(global.hpa_inter_cluster_edges, {
                    from_node_id: _right_node_id, to_node_id: _left_node_id,
                    traversal_cost: 1, is_crossing_edge: true
                });
            }
        }
    }

    // horizontal shared borders: top/bottom neighbors
    for (var _grid_y = 0; _grid_y < (_clusters_down_y - 1); _grid_y++) {
        for (var _grid_x = 0; _grid_x < _clusters_across_x; _grid_x++) {
            var _top_id    = ((_grid_y * _clusters_across_x) + _grid_x);
            var _bottom_id = (_top_id + _clusters_across_x);
            var _top_c     = _clusters_array[_top_id];
            var _bottom_c  = _clusters_array[_bottom_id];
            var _top_bounds = get_cluster_bounds_in_tiles(_top_c.cluster_grid_x, _top_c.cluster_grid_y);

            var _shared_border_tile_y = (_top_bounds.bottom_tile - 1);
            var _x_start_inclusive    = _top_bounds.left_tile;
            var _x_end_inclusive      = (_top_bounds.right_tile - 1);

            var _runs = detect_horizontal_entrance_runs(_shared_border_tile_y, _x_start_inclusive, _x_end_inclusive);
            for (var _r = 0; _r < array_length(_runs); _r++) {
                var _run = _runs[_r];
                var _run_mid_x = ((_run[0] + _run[1]) >> 1);

                var _top_node_id    = create_abstract_node_for_cluster(_top_c,    _run_mid_x, _shared_border_tile_y);
                var _bottom_node_id = create_abstract_node_for_cluster(_bottom_c, _run_mid_x, (_shared_border_tile_y + 1));

                array_push(global.hpa_inter_cluster_edges, {
                    from_node_id: _top_node_id, to_node_id: _bottom_node_id,
                    traversal_cost: 1, is_crossing_edge: true
                });
                array_push(global.hpa_inter_cluster_edges, {
                    from_node_id: _bottom_node_id, to_node_id: _top_node_id,
                    traversal_cost: 1, is_crossing_edge: true
                });
            }
        }
    }
}

#endregion


#region Intra-cluster A* & edges

/// A* limited to cluster bounds (exclusive right/bottom); 4-way movement; Manhattan heuristic
function astar_within_cluster_tiles(_start_tile_x, _start_tile_y, _goal_tile_x, _goal_tile_y, _bounds) {
    var _open_set  = ds_priority_create();
    var _came_from = ds_map_create();
    var _g_score   = ds_map_create();

    var _start_key = (string(_start_tile_x) + "," + string(_start_tile_y));
    var _goal_key  = (string(_goal_tile_x)  + "," + string(_goal_tile_y));

    ds_map_set(_g_score, _start_key, 0);
    ds_priority_add(_open_set, _start_key, 0);

    var _found = false;

    while (!ds_priority_empty(_open_set)) {
        var _current_key = ds_priority_delete_min(_open_set);

        var _pos = parse_tile_key(_current_key);
        var _current_x = _pos.x;
        var _current_y = _pos.y;

        if ((_current_x == _goal_tile_x) && (_current_y == _goal_tile_y)) {
            _found = true;
            break;
        }

        var _dirs = [ [1,0], [-1,0], [0,1], [0,-1] ];
        for (var _i = 0; _i < 4; _i++) {
            var _nx = (_current_x + _dirs[_i][0]);
            var _ny = (_current_y + _dirs[_i][1]);

            // Bounds (exclusive right/bottom)
            if (_nx < _bounds.left_tile)   continue;
            if (_nx >= _bounds.right_tile) continue;
            if (_ny < _bounds.top_tile)    continue;
            if (_ny >= _bounds.bottom_tile) continue;
			
			var _walkable = tile_is_walkable(_nx, _ny);
			show_debug_message("checking tile_is_walkable from astar_within_cluster_tiles | " + string(_walkable))

            if (!_walkable) continue;

            var _neighbor_key = (string(_nx) + "," + string(_ny));

            var _current_g = 0;
            if (ds_map_exists(_g_score, _current_key)) _current_g = ds_map_find_value(_g_score, _current_key);
            var _tentative_g  = (_current_g + 1);

            if (!ds_map_exists(_g_score, _neighbor_key) || (_tentative_g < ds_map_find_value(_g_score, _neighbor_key))) {
                ds_map_set(_came_from, _neighbor_key, _current_key);
                ds_map_set(_g_score,   _neighbor_key, _tentative_g);

                var _h = (abs(_nx - _goal_tile_x) + abs(_ny - _goal_tile_y)); // Manhattan
                var _f = (_tentative_g + _h);
                ds_priority_add(_open_set, _neighbor_key, _f);
            }
        }
    }

    var _result;

    if (_found) {
        var _path_tiles = [];
        var _steps = 0;
        var _walk_key = _goal_key;

        while (_walk_key != _start_key) {
            var _pos = parse_tile_key(_walk_key);
            array_insert(_path_tiles, 0, { x: _pos.x, y: _pos.y });
            _walk_key = ds_map_find_value(_came_from, _walk_key);
            _steps++;
        }
        array_insert(_path_tiles, 0, { x: _start_tile_x, y: _start_tile_y });

        _result = { found: true, cost: _steps, path_tiles: _path_tiles };
    } else {
        _result = { found: false };
    }

    ds_priority_destroy(_open_set);
    ds_map_destroy(_came_from);
    ds_map_destroy(_g_score);

    return _result;
}

/// Build intra-cluster edges between every unordered pair of abstract nodes in each cluster
function build_intra_cluster_edges_for_level(_level_index) {
    var _clusters_array = global.hpa_clusters_by_level[_level_index];

    for (var _c = 0; _c < array_length(_clusters_array); _c++) {
        var _cluster_ref = _clusters_array[_c];
        var _bounds      = get_cluster_bounds_in_tiles(_cluster_ref.cluster_grid_x, _cluster_ref.cluster_grid_y);

        var _node_ids   = _cluster_ref.abstract_nodes;
        var _node_count = array_length(_node_ids);

        for (var _i_left = 0; _i_left < _node_count; _i_left++) {
            for (var _i_right = (_i_left + 1); _i_right < _node_count; _i_right++) {
                var _node_id_a = _node_ids[_i_left];
                var _node_id_b = _node_ids[_i_right];
                var _a = global.hpa_all_abstract_nodes[_node_id_a];
                var _b = global.hpa_all_abstract_nodes[_node_id_b];

                var _res = astar_within_cluster_tiles(_a.tile_x, _a.tile_y, _b.tile_x, _b.tile_y, _bounds);
                if (_res.found) {
                    array_push(_cluster_ref.intra_edges, {
                        from_node_id:     _node_id_a,
                        to_node_id:       _node_id_b,
                        traversal_cost:   _res.cost,
                        stored_tile_path: _res.path_tiles,
                        is_crossing_edge: false
                    });
                    array_push(_cluster_ref.intra_edges, {
                        from_node_id:     _node_id_b,
                        to_node_id:       _node_id_a,
                        traversal_cost:   _res.cost,
                        stored_tile_path: array_reverse(_res.path_tiles),
                        is_crossing_edge: false
                    });
                }
            }
        }
    }
}

#endregion


#region Full build orchestration

function hpa_build_all_levels() {
    for (var _level_index = 0; _level_index < global.hpa_levels_total; _level_index++) {
        build_clusters_for_level(_level_index);
        build_abstract_nodes_and_crossing_edges_for_level(_level_index);
        build_intra_cluster_edges_for_level(_level_index);
    }

    // debug
    show_debug_message("HPA build complete.");
    show_debug_message("Clusters: " + string(global.hpa_clusters_by_level));
    show_debug_message("Nodes   : " + string(global.hpa_all_abstract_nodes));
    show_debug_message("Edges   : " + string(global.hpa_inter_cluster_edges));
}

#endregion

#region High-level abstract search + temporary nodes + refinement

/// Get cluster for a tile (level 0)
function get_cluster_for_tile(_tile_x, _tile_y, _level_index) {
    var _clusters_across_x = floor(HCELLS / CLUSTER_SIZE);
    var _cluster_grid_x    = floor(_tile_x / CLUSTER_SIZE);
    var _cluster_grid_y    = floor(_tile_y / CLUSTER_SIZE);
    var _cluster_id        = ((_cluster_grid_y * _clusters_across_x) + _cluster_grid_x);
    return global.hpa_clusters_by_level[_level_index][_cluster_id];
}

/// find closest abstract node in the same cluster (returns node id or -1)
function hpa_find_abstract_node_for_tile(_tile_x, _tile_y, _level_index) {
    var _cluster_ref = get_cluster_for_tile(_tile_x, _tile_y, _level_index);
    if (is_undefined(_cluster_ref)) return -1;
    var _closest_node_id = -1;
    var _closest_dist_sq = infinity;

    for (var _i = 0; _i < array_length(_cluster_ref.abstract_nodes); _i++) {
        var _node_id = _cluster_ref.abstract_nodes[_i];
        var _node_ref = global.hpa_all_abstract_nodes[_node_id];
        var _dx = (_node_ref.tile_x - _tile_x);
        var _dy = (_node_ref.tile_y - _tile_y);
        var _dist_sq = (_dx * _dx + _dy * _dy);
        if (_dist_sq < _closest_dist_sq) {
            _closest_dist_sq = _dist_sq;
            _closest_node_id = _node_id;
        }
    }
    return _closest_node_id;
}

/// Build lookup map for intra edges: "from,to" -> stored_tile_path
function build_intra_edge_lookup_map(_level_index) {
    var _lookup = ds_map_create();
    var _clusters_array = global.hpa_clusters_by_level[_level_index];
    for (var _c = 0; _c < array_length(_clusters_array); _c++) {
        var _cluster_ref = _clusters_array[_c];
        var _edges = _cluster_ref.intra_edges;
        for (var _i = 0; _i < array_length(_edges); _i++) {
            var _e = _edges[_i];
            var _key = (string(_e.from_node_id) + "," + string(_e.to_node_id));
            ds_map_set(_lookup, _key, _e.stored_tile_path);
        }
    }
    return _lookup;
}

/// collect outgoing edges for a node (intra + inter + temp)
function collect_outgoing_edges(_from_node_id, _level_index, _temp_edges_by_from, _clusters_array) {
    var _edges_out = [];

    // temp edges
    var _from_key = string(_from_node_id);
    if (ds_map_exists(_temp_edges_by_from, _from_key)) {
        var _temp_list = ds_map_find_value(_temp_edges_by_from, _from_key);
        for (var _t = 0; _t < array_length(_temp_list); _t++) array_push(_edges_out, _temp_list[_t]);
    }

    // intra edges (if permanent node)
    if ((_from_node_id >= 0)) {
        var _node = global.hpa_all_abstract_nodes[_from_node_id];
        var _cluster_id = _node.owner_cluster_id;
        var _cluster_ref = _clusters_array[_cluster_id];
        var _intra = _cluster_ref.intra_edges;
        for (var _i = 0; _i < array_length(_intra); _i++) {
            var _e = _intra[_i];
            if (_e.from_node_id == _from_node_id) {
                array_push(_edges_out, {
                    to_node_id: _e.to_node_id,
                    traversal_cost: _e.traversal_cost,
                    kind: "intra",
                    stored_tile_path: _e.stored_tile_path
                });
            }
        }
    }

    // inter-cluster edges (global)
    var _inter = global.hpa_inter_cluster_edges;
    for (var _k = 0; _k < array_length(_inter); _k++) {
        var _e2 = _inter[_k];
        if (_e2.from_node_id == _from_node_id) {
            array_push(_edges_out, {
                to_node_id: _e2.to_node_id,
                traversal_cost: _e2.traversal_cost,
                kind: "inter"
            });
        }
    }

    return _edges_out;
}

/// create temp edges from a tile (temp node) to cluster nodes and node->temp reverse entries
function make_temp_edges_for_tile(_tile_x, _tile_y, _temp_node_id, _cluster_ref, _level_index, _temp_edges_by_from) {
    var _bounds = get_cluster_bounds_in_tiles(_cluster_ref.cluster_grid_x, _cluster_ref.cluster_grid_y);
    var _node_ids = _cluster_ref.abstract_nodes;

    var _out_from_temp = [];

    for (var _i = 0; _i < array_length(_node_ids); _i++) {
        var _node_id = _node_ids[_i];
        var _n = global.hpa_all_abstract_nodes[_node_id];

        var _res = astar_within_cluster_tiles(_tile_x, _tile_y, _n.tile_x, _n.tile_y, _bounds);
        if (_res.found) {
            // temp -> node
            array_push(_out_from_temp, {
                to_node_id: _node_id,
                traversal_cost: _res.cost,
                kind: "temp",
                stored_tile_path: _res.path_tiles
            });

            // node -> temp (store under node's from list)
            var _node_key = string(_node_id);
            var _list_for_node = [];
            if (ds_map_exists(_temp_edges_by_from, _node_key)) _list_for_node = ds_map_find_value(_temp_edges_by_from, _node_key);
            array_push(_list_for_node, {
                to_node_id: _temp_node_id,
                traversal_cost: _res.cost,
                kind: "temp",
                stored_tile_path: array_reverse(_res.path_tiles)
            });
            ds_map_set(_temp_edges_by_from, _node_key, _list_for_node);
        }
    }

    // store outgoing from temp node
    ds_map_set(_temp_edges_by_from, string(_temp_node_id), _out_from_temp);
}

/// A* on abstract graph using temporary edges map
function abstract_astar_nodes(_start_node_id, _goal_node_id, _level_index, _temp_start_node, _temp_goal_node, _temp_edges_by_from) {
    var _clusters_array = global.hpa_clusters_by_level[_level_index];

    var _open_set = ds_priority_create();
    var _came_from = ds_map_create();
    var _g_score = ds_map_create();

    ds_map_set(_g_score, string(_start_node_id), 0);
    ds_priority_add(_open_set, string(_start_node_id), 0);

    var _found = false;

    while (!ds_priority_empty(_open_set)) {
        var _current_key = ds_priority_delete_min(_open_set);
        var _current_id = real(_current_key);

        if (_current_id == _goal_node_id) { _found = true; break; }

        var _neighbors = collect_outgoing_edges(_current_id, _level_index, _temp_edges_by_from, _clusters_array);

        var _current_g = 0;
        if (ds_map_exists(_g_score, _current_key)) _current_g = ds_map_find_value(_g_score, _current_key);

        for (var _i = 0; _i < array_length(_neighbors); _i++) {
            var _edge = _neighbors[_i];
            var _to_id = _edge.to_node_id;
            var _to_key = string(_to_id);

            var _tentative_g = (_current_g + _edge.traversal_cost);

            if (!ds_map_exists(_g_score, _to_key) || (_tentative_g < ds_map_find_value(_g_score, _to_key))) {
                ds_map_set(_came_from, _to_key, _current_key);
                ds_map_set(_g_score, _to_key, _tentative_g);

                var _to_xy = get_node_tile_xy(_to_id, _temp_start_node, _temp_goal_node);
                var _h = (abs(_to_xy.x - _temp_goal_node.tile_x) + abs(_to_xy.y - _temp_goal_node.tile_y)); // Manhattan to goal tile
                var _f = (_tentative_g + _h);
                ds_priority_add(_open_set, _to_key, _f);
            }
        }
    }

    var _result;
    if (_found) {
        var _path_node_ids = [];
        var _walk_key = string(_goal_node_id);
        while (_walk_key != string(_start_node_id)) {
            array_insert(_path_node_ids, 0, real(_walk_key));
            _walk_key = ds_map_find_value(_came_from, _walk_key);
        }
        array_insert(_path_node_ids, 0, real(string(_start_node_id)));
        _result = { found: true, path_node_ids: _path_node_ids };
    } else {
        _result = { found: false };
    }

    ds_priority_destroy(_open_set);
    ds_map_destroy(_came_from);
    ds_map_destroy(_g_score);

    return _result;
}

/// Convert node id -> tile coords, supports temp nodes (-1,-2)
function get_node_tile_xy(_node_id, _temp_start_node, _temp_goal_node) {
    if ((_node_id == _temp_start_node.node_id)) return { x: _temp_start_node.tile_x, y: _temp_start_node.tile_y };
    if ((_node_id == _temp_goal_node.node_id))  return { x: _temp_goal_node.tile_x,  y: _temp_goal_node.tile_y  };
    var _n = global.hpa_all_abstract_nodes[_node_id];
    return { x: _n.tile_x, y: _n.tile_y };
}

/// refine abstract node path into a tile-by-tile path
function refine_abstract_path_to_tiles(_path_node_ids, _level_index, _temp_edges_by_from, _temp_start_node, _temp_goal_node) {
    var _tile_path = [];

    var _intra_lookup = build_intra_edge_lookup_map(_level_index);

    // helper to append segment and avoid duplicating first tile
    function _append_segment(_seg_tiles) {
        if (array_length(_seg_tiles) == 0) return;
        if (array_length(_tile_path) == 0) {
            for (var _i = 0; _i < array_length(_seg_tiles); _i++) array_push(_tile_path, _seg_tiles[_i]);
        } else {
            for (var _i = 1; _i < array_length(_seg_tiles); _i++) array_push(_tile_path, _seg_tiles[_i]);
        }
    }

    for (var _i = 0; _i < (array_length(_path_node_ids) - 1); _i++) {
        var _from_id = _path_node_ids[_i];
        var _to_id   = _path_node_ids[_i + 1];

        var _key_from = string(_from_id);
        var _key_intra = (string(_from_id) + "," + string(_to_id));

        var _segment_found = false;

        // 1) check temp edges from _from_id
        if (ds_map_exists(_temp_edges_by_from, _key_from)) {
            var _arr = ds_map_find_value(_temp_edges_by_from, _key_from);
            for (var _t = 0; _t < array_length(_arr); _t++) {
                var _e = _arr[_t];
                if (_e.to_node_id == _to_id) {
                    _append_segment(_e.stored_tile_path);
                    _segment_found = true;
                    break;
                }
            }
            if (_segment_found) continue;
        }

        // 2) intra edge?
        if (ds_map_exists(_intra_lookup, _key_intra)) {
            var _stored = ds_map_find_value(_intra_lookup, _key_intra);
            _append_segment(_stored);
            _segment_found = true;
            continue;
        }

        // 3) inter edge -> single step from node tile to neighbor tile
        var _from_xy = get_node_tile_xy(_from_id, _temp_start_node, _temp_goal_node);
        var _to_xy   = get_node_tile_xy(_to_id,   _temp_start_node, _temp_goal_node);
        var _dx = (_to_xy.x - _from_xy.x);
        var _dy = (_to_xy.y - _from_xy.y);

        if (((abs(_dx) + abs(_dy)) == 1)) {
            var _seg = [ { x: _from_xy.x, y: _from_xy.y }, { x: _to_xy.x, y: _to_xy.y } ];
            _append_segment(_seg);
            _segment_found = true;
        }

        if (!_segment_found) {
            show_debug_message("HPA refine: missing segment from " + string(_from_id) + " to " + string(_to_id));
        }
    }

    ds_map_destroy(_intra_lookup);
    return _tile_path;
}

/// Main query function: returns { found, tile_path:[{x,y},...] }
function hpa_find_path_tiles(_start_tile_x, _start_tile_y, _goal_tile_x, _goal_tile_y, _level_index) {
    // same-cluster fast path
    var _start_cluster = get_cluster_for_tile(_start_tile_x, _start_tile_y, _level_index);
    var _goal_cluster  = get_cluster_for_tile(_goal_tile_x,  _goal_tile_y,  _level_index);

    if ((_start_cluster.cluster_id == _goal_cluster.cluster_id)) {
        var _bounds = get_cluster_bounds_in_tiles(_start_cluster.cluster_grid_x, _start_cluster.cluster_grid_y);
        var _resdir = astar_within_cluster_tiles(_start_tile_x, _start_tile_y, _goal_tile_x, _goal_tile_y, _bounds);
        if (_resdir.found) return { found: true, tile_path: _resdir.path_tiles };
        // else fall through to abstract routing
    }

    // temp nodes (negative identifiers)
    var _temp_start_node = { node_id: (-1), tile_x: _start_tile_x, tile_y: _start_tile_y };
    var _temp_goal_node  = { node_id: (-2), tile_x: _goal_tile_x,  tile_y: _goal_tile_y  };

    var _temp_edges_by_from = ds_map_create();

    // connect temp nodes to their cluster nodes
    make_temp_edges_for_tile(_start_tile_x, _start_tile_y, _temp_start_node.node_id, _start_cluster, _level_index, _temp_edges_by_from);
    make_temp_edges_for_tile(_goal_tile_x,  _goal_tile_y,  _temp_goal_node.node_id,  _goal_cluster,  _level_index, _temp_edges_by_from);

    // run abstract A*
    var _abstract_res = abstract_astar_nodes(_temp_start_node.node_id, _temp_goal_node.node_id, _level_index, _temp_start_node, _temp_goal_node, _temp_edges_by_from);
    if (!_abstract_res.found) { ds_map_destroy(_temp_edges_by_from); return { found: false }; }

    // refine to tile path
    var _tile_path = refine_abstract_path_to_tiles(_abstract_res.path_node_ids, _level_index, _temp_edges_by_from, _temp_start_node, _temp_goal_node);

    ds_map_destroy(_temp_edges_by_from);
    return { found: (array_length(_tile_path) > 0), tile_path: _tile_path };
}

#endregion

hpa_build_all_levels();

#region Debug

surf_hpa = -1;

#endregion