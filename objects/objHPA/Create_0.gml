// -----------------------------
// MULTI-LEVEL HPA* (clean, DS-PQ only)
// - Uses HCELLS/VCELLS and TILE_SIZE_PIXELS
// - Uses structs/arrays; only ds_* allowed: ds_priority
// - All referenced functions included; no unused functions
// -----------------------------

/// CONFIG: set cluster sizes per level (example)
global.hpa_cluster_sizes = [8, 4, 2]; // level0 cluster size in tiles, level1 = number of level0 clusters per side, etc.
global.hpa_levels_total = array_length(global.hpa_cluster_sizes);

// Precomputed structures (filled by hpa_build_all_levels)
global.hpa_cluster_tile_size_by_level = [];
global.hpa_cluster_grid_counts_by_level = []; // array of { across_x, down_y }
global.hpa_clusters_by_level = [];            // per-level arrays of cluster structs
global.hpa_all_abstract_nodes = [];           // index by node_id -> node struct
global.hpa_next_abstract_node_id = 0;
global.hpa_inter_cluster_edges_by_level = []; // per-level arrays of inter edges

#macro TILE_SIZE_PIXELS 8
#macro HCELLS floor(room_width / TILE_SIZE_PIXELS)
#macro VCELLS floor(room_height / TILE_SIZE_PIXELS)

var _lay_id = layer_get_id("Tiles_1");
map_id = layer_tilemap_get_id(_lay_id);

// -------------------- REQUIRED: you may adapt this --------------------

// Convert tile -> pixel (top-left)
function tile_to_pixel(_tile_x, _tile_y) {
    return { x: _tile_x * TILE_SIZE_PIXELS, y: _tile_y * TILE_SIZE_PIXELS };
}

// Replace with your game's tilewalkable/collision detection
function tile_is_walkable(_tile_x, _tile_y) {
    if (_tile_x < 0 || _tile_y < 0) return false;
    if (_tile_x >= HCELLS || _tile_y >= VCELLS) return false;

	var _tile = tilemap_get(map_id, _tile_x, _tile_y);
	
	if (_tile > 0) return false;
    return true;
}

// -------------------- CORE BUILD HELPERS --------------------

// Compute tile-size per cluster at each level (product of sizes)
function hpa_compute_cluster_tile_size_by_level() {
    global.hpa_cluster_tile_size_by_level = [];
    var _prod = 1;
    for (var _level = 0; _level < global.hpa_levels_total; _level++) {
        _prod *= global.hpa_cluster_sizes[_level];
        array_push(global.hpa_cluster_tile_size_by_level, _prod);
    }
}

// Build cluster grid for a single level
function hpa_build_clusters_for_level(_level_index) {
    var _clusters = [];
    var _cluster_tile_size = global.hpa_cluster_tile_size_by_level[_level_index];

    var _across_x = ceil(HCELLS / _cluster_tile_size);
    var _down_y   = ceil(VCELLS / _cluster_tile_size);

    global.hpa_cluster_grid_counts_by_level[_level_index] = { across_x: _across_x, down_y: _down_y };

    for (var _gy = 0; _gy < _down_y; _gy++) {
        for (var _gx = 0; _gx < _across_x; _gx++) {
            var _cluster_id = (_gy * _across_x) + _gx;
            var _left_tile   = _gx * _cluster_tile_size;
            var _top_tile    = _gy * _cluster_tile_size;
            var _right_tile  = min(_left_tile + _cluster_tile_size, HCELLS); // exclusive
            var _bottom_tile = min(_top_tile  + _cluster_tile_size, VCELLS); // exclusive

            var _cluster_struct = {
                level_index: _level_index,
                cluster_id: _cluster_id,
                cluster_grid_x: _gx,
                cluster_grid_y: _gy,
                bounds: { left_tile: _left_tile, top_tile: _top_tile, right_tile: _right_tile, bottom_tile: _bottom_tile },
                abstract_nodes: [], // node ids
                intra_edges: []    // edges inside this cluster
            };

            _clusters[_cluster_id] = _cluster_struct;
        }
    }

    global.hpa_clusters_by_level[_level_index] = _clusters;
}

// Detect vertical continuous walkable runs across a vertical border column (inclusive y)
function detect_vertical_entrance_runs(_border_tile_x, _tile_y_start_inclusive, _tile_y_end_inclusive) {
    var _runs = [];
    var _in_run = false;
    var _run_start = -1;
    for (var _y = _tile_y_start_inclusive; _y <= _tile_y_end_inclusive; _y++) {
        var _left_walkable  = tile_is_walkable(_border_tile_x, _y);
        var _right_walkable = tile_is_walkable(_border_tile_x + 1, _y);
        var _can_cross = (_left_walkable && _right_walkable);
        if (_can_cross && !_in_run) { _in_run = true; _run_start = _y; }
        if ((!_can_cross || _y == _tile_y_end_inclusive) && _in_run) {
            var _run_end = _can_cross ? _y : (_y - 1);
            array_push(_runs, [_run_start, _run_end]);
            _in_run = false;
        }
    }
    return _runs;
}

// Detect horizontal continuous walkable runs across a horizontal border row (inclusive x)
function detect_horizontal_entrance_runs(_border_tile_y, _tile_x_start_inclusive, _tile_x_end_inclusive) {
    var _runs = [];
    var _in_run = false;
    var _run_start = -1;
    for (var _x = _tile_x_start_inclusive; _x <= _tile_x_end_inclusive; _x++) {
        var _top_walkable    = tile_is_walkable(_x, _border_tile_y);
        var _bottom_walkable = tile_is_walkable(_x, _border_tile_y + 1);
        var _can_cross = (_top_walkable && _bottom_walkable);
        if (_can_cross && !_in_run) { _in_run = true; _run_start = _x; }
        if ((!_can_cross || _x == _tile_x_end_inclusive) && _in_run) {
            var _run_end = _can_cross ? _x : (_x - 1);
            array_push(_runs, [_run_start, _run_end]);
            _in_run = false;
        }
    }
    return _runs;
}

// Create and register an abstract node (tile coords) and attach to a cluster
function create_abstract_node_for_cluster(_cluster_ref, _level_index, _tile_x, _tile_y) {
    var _node_id = global.hpa_next_abstract_node_id;
    global.hpa_next_abstract_node_id++;

    var _pixel_pos = tile_to_pixel(_tile_x, _tile_y);
    var _node_struct = {
        node_id: _node_id,
        level_index: _level_index,
        owner_cluster_id: _cluster_ref.cluster_id,
        owner_cluster_grid_x: _cluster_ref.cluster_grid_x,
        owner_cluster_grid_y: _cluster_ref.cluster_grid_y,
        tile_x: _tile_x,
        tile_y: _tile_y,
        x: _pixel_pos.x,
        y: _pixel_pos.y
    };

    global.hpa_all_abstract_nodes[_node_id] = _node_struct;
    array_push(_cluster_ref.abstract_nodes, _node_id);
    return _node_id;
}

// Build vertical crossing nodes/edges for a level
function build_vertical_crossings_for_level(_level_index) {
    var _clusters = global.hpa_clusters_by_level[_level_index];
    var _counts = global.hpa_cluster_grid_counts_by_level[_level_index];
    var _across = _counts.across_x;
    var _down = _counts.down_y;

    var _inter_edges = [];

    for (var _gy = 0; _gy < _down; _gy++) {
        for (var _gx = 0; _gx < _across - 1; _gx++) {
            var _left_id = (_gy * _across) + _gx;
            var _right_id = _left_id + 1;
            var _left_cluster = _clusters[_left_id];

            var _bounds_left = _left_cluster.bounds;
            var _shared_border_x = _bounds_left.right_tile - 1; // rightmost col of left cluster (inclusive)
            var _y0 = _bounds_left.top_tile;
            var _y1 = _bounds_left.bottom_tile - 1;

            var _runs = detect_vertical_entrance_runs(_shared_border_x, _y0, _y1);
            for (var _r = 0; _r < array_length(_runs); _r++) {
                var _run = _runs[_r];
                var _mid_y = ((_run[0] + _run[1]) >> 1);

                var _left_node_id = create_abstract_node_for_cluster(_left_cluster, _level_index, _shared_border_x, _mid_y);
                var _right_cluster = global.hpa_clusters_by_level[_level_index][_right_id];
                var _right_node_id = create_abstract_node_for_cluster(_right_cluster, _level_index, (_shared_border_x + 1), _mid_y);

                var _seg = [ { x: _shared_border_x, y: _mid_y }, { x: (_shared_border_x + 1), y: _mid_y } ];
                array_push(_inter_edges, { from_node_id: _left_node_id, to_node_id: _right_node_id, traversal_cost: 1, stored_tile_path: _seg, is_crossing_edge: true });
                array_push(_inter_edges, { from_node_id: _right_node_id, to_node_id: _left_node_id, traversal_cost: 1, stored_tile_path: array_reverse(_seg), is_crossing_edge: true });
            }
        }
    }

    global.hpa_inter_cluster_edges_by_level[_level_index] = _inter_edges;
}

// Build horizontal crossing nodes/edges for a level
function build_horizontal_crossings_for_level(_level_index) {
    var _clusters = global.hpa_clusters_by_level[_level_index];
    var _counts = global.hpa_cluster_grid_counts_by_level[_level_index];
    var _across = _counts.across_x;
    var _down = _counts.down_y;

    var _inter_edges = is_array(global.hpa_inter_cluster_edges_by_level[_level_index]) ? global.hpa_inter_cluster_edges_by_level[_level_index] : [];

    for (var _gy = 0; _gy < _down - 1; _gy++) {
        for (var _gx = 0; _gx < _across; _gx++) {
            var _top_id = (_gy * _across) + _gx;
            var _bot_id = _top_id + _across;
            var _top_cluster = _clusters[_top_id];

            var _bounds_top = _top_cluster.bounds;
            var _shared_border_y = _bounds_top.bottom_tile - 1;
            var _x0 = _bounds_top.left_tile;
            var _x1 = _bounds_top.right_tile - 1;

            var _runs = detect_horizontal_entrance_runs(_shared_border_y, _x0, _x1);
            for (var _r = 0; _r < array_length(_runs); _r++) {
                var _run = _runs[_r];
                var _mid_x = ((_run[0] + _run[1]) >> 1);

                var _top_node_id = create_abstract_node_for_cluster(_top_cluster, _level_index, _mid_x, _shared_border_y);
                var _bot_cluster = global.hpa_clusters_by_level[_level_index][_bot_id];
                var _bot_node_id = create_abstract_node_for_cluster(_bot_cluster, _level_index, _mid_x, (_shared_border_y + 1));

                var _seg = [ { x: _mid_x, y: _shared_border_y }, { x: _mid_x, y: (_shared_border_y + 1) } ];
                array_push(_inter_edges, { from_node_id: _top_node_id, to_node_id: _bot_node_id, traversal_cost: 1, stored_tile_path: _seg, is_crossing_edge: true });
                array_push(_inter_edges, { from_node_id: _bot_node_id, to_node_id: _top_node_id, traversal_cost: 1, stored_tile_path: array_reverse(_seg), is_crossing_edge: true });
            }
        }
    }

    global.hpa_inter_cluster_edges_by_level[_level_index] = _inter_edges;
}

// Build abstract nodes and inter-cluster (crossing) edges for a level
function hpa_build_abstract_nodes_and_crossings_for_level(_level_index) {
    if (!is_array(global.hpa_clusters_by_level[_level_index])) return;
    global.hpa_inter_cluster_edges_by_level[_level_index] = [];
    build_vertical_crossings_for_level(_level_index);
    build_horizontal_crossings_for_level(_level_index);
}

// -------------------- TILE A* (constrained to cluster bounds) --------------------
// Using ds_priority for open set. came_from and g_score are structs keyed by "x,y".

function astar_within_cluster_tiles(_start_tile_x, _start_tile_y, _goal_tile_x, _goal_tile_y, _bounds) {
    var _open_pq = ds_priority_create();
    var _came = {}; // struct: key -> parent_key
    var _g_score = {}; // struct: key -> g value

    var _start_key = string(_start_tile_x) + "," + string(_start_tile_y);
    var _goal_key  = string(_goal_tile_x)  + "," + string(_goal_tile_y);

    _g_score[$ _start_key] = 0;
    ds_priority_add(_open_pq, _start_key, 0);

    var _found = false;

    while (!ds_priority_empty(_open_pq)) {
        var _current_key = ds_priority_delete_min(_open_pq);
        if (is_undefined(_current_key)) break;
        var _parts = string_split(_current_key, ",");
        var _cx = real(_parts[0]), _cy = real(_parts[1]);

        if (_cx == _goal_tile_x && _cy == _goal_tile_y) { _found = true; break; }

        var _dirs = [ [1,0], [-1,0], [0,1], [0,-1] ];
        var _current_g = is_undefined(_g_score[$ _current_key]) ? 0 : _g_score[$ _current_key];

        for (var _d = 0; _d < 4; _d++) {
            var _nx = _cx + _dirs[_d][0];
            var _ny = _cy + _dirs[_d][1];

            if (_nx < _bounds.left_tile) continue;
            if (_nx >= _bounds.right_tile) continue;
            if (_ny < _bounds.top_tile) continue;
            if (_ny >= _bounds.bottom_tile) continue;

            if (!tile_is_walkable(_nx, _ny)) continue;

            var _nkey = string(_nx) + "," + string(_ny);
            var _tentative_g = _current_g + 1;

            if (is_undefined(_g_score[$ _nkey]) || (_tentative_g < _g_score[$ _nkey])) {
                _came[$ _nkey] = _current_key;
                _g_score[$ _nkey] = _tentative_g;
                var _h = abs(_nx - _goal_tile_x) + abs(_ny - _goal_tile_y);
                ds_priority_add(_open_pq, _nkey, _tentative_g + _h);
            }
        }
    }

    var _result;
    if (_found) {
        var _path_tiles = [];
        var _walk_key = _goal_key;
        while (_walk_key != _start_key) {
            var _p = string_split(_walk_key, ",");
            array_insert(_path_tiles, 0, { x: real(_p[0]), y: real(_p[1]) });
            _walk_key = _came[$ _walk_key];
        }
        array_insert(_path_tiles, 0, { x: _start_tile_x, y: _start_tile_y });
        _result = { found: true, cost: array_length(_path_tiles) - 1, path_tiles: _path_tiles };
    } else {
        _result = { found: false };
    }

    ds_priority_destroy(_open_pq);
    return _result;
}

// -------------------- GRAPH A* ON EDGES (child-level graph) --------------------
// _edges_by_from is a struct keyed by "node_id" string -> array of edge structs

function astar_on_edges(_start_node_id, _goal_node_id, _edges_by_from) {
    var _open_pq = ds_priority_create();
    var _came = {}; // struct: node_key -> parent_node_key
    var _g_score = {}; // struct: node_key -> g value

    var _start_key = string(_start_node_id);
    _g_score[$ _start_key] = 0;
    ds_priority_add(_open_pq, _start_key, 0);

    var _found = false;

    while (!ds_priority_empty(_open_pq)) {
        var _current_key = ds_priority_delete_min(_open_pq);
        if (is_undefined(_current_key)) break;
        var _current_id = real(_current_key);

        if (_current_id == _goal_node_id) { _found = true; break; }

        var _neighbors = is_undefined(_edges_by_from[$ _current_key]) ? [] : _edges_by_from[$ _current_key];
        var _current_g = is_undefined(_g_score[$ _current_key]) ? 0 : _g_score[$ _current_key];

        for (var _i = 0; _i < array_length(_neighbors); _i++) {
            var _edge = _neighbors[_i];
            var _to_key = string(_edge.to_node_id);
            var _tent = _current_g + _edge.traversal_cost;
            if (is_undefined(_g_score[$ _to_key]) || (_tent < _g_score[$ _to_key])) {
                _came[$ _to_key] = _current_key;
                _g_score[$ _to_key] = _tent;
                ds_priority_add(_open_pq, _to_key, _tent); // no extra heuristic here (Dijkstra-like)
            }
        }
    }

    var _result;
    if (_found) {
        var _path = [];
        var _walk = string(_goal_node_id);
        while (_walk != string(_start_node_id)) {
            array_insert(_path, 0, real(_walk));
            _walk = _came[$ _walk];
        }
        array_insert(_path, 0, real(string(_start_node_id)));
        _result = { found: true, path_node_ids: _path };
    } else {
        _result = { found: false };
    }

    ds_priority_destroy(_open_pq);
    return _result;
}

// -------------------- BUILD INTRA-CLUSTER EDGES (multi-level) --------------------

// Build lookup struct "from,to" -> stored_tile_path for a level
function build_intra_edge_lookup_map_for_level(_level_index) {
    var _lookup = {};
    var _clusters = global.hpa_clusters_by_level[_level_index];
    if (!is_array(_clusters)) return _lookup;
    for (var _c = 0; _c < array_length(_clusters); _c++) {
        var _cluster = _clusters[_c];
        if (!is_array(_cluster.intra_edges)) continue;
        for (var _e = 0; _e < array_length(_cluster.intra_edges); _e++) {
            var _edge = _cluster.intra_edges[_e];
            var _key = string(_edge.from_node_id) + "," + string(_edge.to_node_id);
            _lookup[$ _key] = _edge.stored_tile_path;
        }
    }
    var _inter = global.hpa_inter_cluster_edges_by_level[_level_index];
    if (is_array(_inter)) {
        for (var _i = 0; _i < array_length(_inter); _i++) {
            var _edge = _inter[_i];
            var _k = string(_edge.from_node_id) + "," + string(_edge.to_node_id);
            _lookup[$ _k] = _edge.stored_tile_path;
        }
    }
    return _lookup;
}

// Build intra edges for each cluster at a given level
function build_intra_cluster_edges_for_level(_level_index) {
    var _clusters = global.hpa_clusters_by_level[_level_index];
    if (!is_array(_clusters)) return;

    var _child_level = _level_index - 1;
    var _child_intra_lookup = undefined;
    var _child_inter_edges = undefined;
    if (_level_index > 0) {
        _child_intra_lookup = build_intra_edge_lookup_map_for_level(_child_level);
        _child_inter_edges = global.hpa_inter_cluster_edges_by_level[_child_level];
    }

    for (var _c = 0; _c < array_length(_clusters); _c++) {
        var _cluster = _clusters[_c];
        _cluster.intra_edges = [];
        var _node_ids = _cluster.abstract_nodes;
        var _count = array_length(_node_ids);

        for (var _i = 0; _i < _count; _i++) {
            for (var _j = _i + 1; _j < _count; _j++) {
                var _a_id = _node_ids[_i];
                var _b_id = _node_ids[_j];
                var _a_node = global.hpa_all_abstract_nodes[_a_id];
                var _b_node = global.hpa_all_abstract_nodes[_b_id];

                if (_level_index == 0) {
                    // tile-level A*
                    var _res = astar_within_cluster_tiles(_a_node.tile_x, _a_node.tile_y, _b_node.tile_x, _b_node.tile_y, _cluster.bounds);
                    if (_res.found) {
                        array_push(_cluster.intra_edges, { from_node_id: _a_id, to_node_id: _b_id, traversal_cost: _res.cost, stored_tile_path: _res.path_tiles, is_crossing_edge: false });
                        array_push(_cluster.intra_edges, { from_node_id: _b_id, to_node_id: _a_id, traversal_cost: _res.cost, stored_tile_path: array_reverse(_res.path_tiles), is_crossing_edge: false });
                    }
                } else {
                    // Build adjacency of child-level nodes (struct keyed by "node_id")
                    var _adj = {};
                    // Add child intra edges from all child clusters
                    var _child_clusters = global.hpa_clusters_by_level[_child_level];
                    for (var _cc = 0; _cc < array_length(_child_clusters); _cc++) {
                        var _child_cl = _child_clusters[_cc];
                        if (!is_array(_child_cl.intra_edges)) continue;
                        for (var _ei = 0; _ei < array_length(_child_cl.intra_edges); _ei++) {
                            var _edge = _child_cl.intra_edges[_ei];
                            var _fromk = string(_edge.from_node_id);
                            var _lst = is_undefined(_adj[$ _fromk]) ? [] : _adj[$ _fromk];
                            array_push(_lst, { from_node_id: _edge.from_node_id, to_node_id: _edge.to_node_id, traversal_cost: _edge.traversal_cost, stored_tile_path: _edge.stored_tile_path, is_crossing_edge: _edge.is_crossing_edge });
                            _adj[$ _fromk] = _lst;
                        }
                    }
                    // Add child inter edges
                    if (is_array(_child_inter_edges)) {
                        for (var _ci = 0; _ci < array_length(_child_inter_edges); _ci++) {
                            var _e2 = _child_inter_edges[_ci];
                            var _fk = string(_e2.from_node_id);
                            var _lst2 = is_undefined(_adj[$ _fk]) ? [] : _adj[$ _fk];
                            array_push(_lst2, { from_node_id: _e2.from_node_id, to_node_id: _e2.to_node_id, traversal_cost: _e2.traversal_cost, stored_tile_path: _e2.stored_tile_path, is_crossing_edge: _e2.is_crossing_edge });
                            _adj[$ _fk] = _lst2;
                        }
                    }

                    // Run graph A* over child graph to connect _a_id -> _b_id
                    var _graph_res = astar_on_edges(_a_id, _b_id, _adj);
                    if (_graph_res.found) {
                        // Compose stored tile path using child lookup (struct)
                        var _child_lookup = {};
                        if (!is_undefined(_child_intra_lookup)) {
                            var _names = variable_struct_get_names(_child_intra_lookup);
                            for (var _ni = 0; _ni < array_length(_names); _ni++) {
                                var _k = _names[_ni];
                                _child_lookup[$ _k] = _child_intra_lookup[$ _k];
                            }
                        }
                        if (is_array(_child_inter_edges)) {
                            for (var _ci2 = 0; _ci2 < array_length(_child_inter_edges); _ci2++) {
                                var _ce = _child_inter_edges[_ci2];
                                var _key = string(_ce.from_node_id) + "," + string(_ce.to_node_id);
                                _child_lookup[$ _key] = _ce.stored_tile_path;
                            }
                        }

                        var _composed_tiles = [];
                        var _path_nodes = _graph_res.path_node_ids;
                        for (var _p = 0; _p < (array_length(_path_nodes) - 1); _p++) {
                            var _fromn = _path_nodes[_p];
                            var _ton = _path_nodes[_p + 1];
                            var _kseg = string(_fromn) + "," + string(_ton);
                            var _seg = is_undefined(_child_lookup[$ _kseg]) ? undefined : _child_lookup[$ _kseg];
                            if (is_undefined(_seg)) {
                                var _fa = global.hpa_all_abstract_nodes[_fromn];
                                var _ta = global.hpa_all_abstract_nodes[_ton];
                                _seg = [ { x: _fa.tile_x, y: _fa.tile_y }, { x: _ta.tile_x, y: _ta.tile_y } ];
                            }
                            if (array_length(_composed_tiles) == 0) {
                                for (var _z = 0; _z < array_length(_seg); _z++) array_push(_composed_tiles, _seg[_z]);
                            } else {
                                for (var _z = 1; _z < array_length(_seg); _z++) array_push(_composed_tiles, _seg[_z]);
                            }
                        }

                        // Compute total cost by summing adjacency edge costs along path
                        var _total_cost = 0;
                        for (var _p2 = 0; _p2 < (array_length(_path_nodes) - 1); _p2++) {
                            var _fromn2 = _path_nodes[_p2];
                            var _ton2 = _path_nodes[_p2 + 1];
                            var _alist = is_undefined(_adj[$ string(_fromn2)]) ? [] : _adj[$ string(_fromn2)];
                            for (var _li = 0; _li < array_length(_alist); _li++) {
                                if (_alist[_li].to_node_id == _ton2) { _total_cost += _alist[_li].traversal_cost; break; }
                            }
                        }

                        array_push(_cluster.intra_edges, { from_node_id: _a_id, to_node_id: _b_id, traversal_cost: _total_cost, stored_tile_path: _composed_tiles, is_crossing_edge: false });
                        array_push(_cluster.intra_edges, { from_node_id: _b_id, to_node_id: _a_id, traversal_cost: _total_cost, stored_tile_path: array_reverse(_composed_tiles), is_crossing_edge: false });
                    }
                }
            }
        }
    }
}

// -------------------- TEMP EDGES & OUTGOING COLLECTION --------------------

// Get tile coordinates for a node id; supports temp nodes (-1/-2)
function get_node_tile_xy(_node_id, _temp_start_node, _temp_goal_node) {
    if (_node_id == _temp_start_node.node_id) return { x: _temp_start_node.tile_x, y: _temp_start_node.tile_y };
    if (_node_id == _temp_goal_node.node_id) return { x: _temp_goal_node.tile_x, y: _temp_goal_node.tile_y };
    var _n = global.hpa_all_abstract_nodes[_node_id];
    return { x: _n.tile_x, y: _n.tile_y };
}

// Make temp edges connecting a tile (temp node) to each abstract node in its cluster.
// Also creates reverse node->temp entries inside _temp_edges_by_from struct.
function make_temp_edges_for_tile_at_level(_tile_x, _tile_y, _temp_node_id, _cluster_ref, _level_index, _temp_edges_by_from) {
    var _bounds = _cluster_ref.bounds;
    var _node_ids = _cluster_ref.abstract_nodes;
    var _out_from_temp = [];
    for (var _i = 0; _i < array_length(_node_ids); _i++) {
        var _nid = _node_ids[_i];
        var _node = global.hpa_all_abstract_nodes[_nid];
        var _res = astar_within_cluster_tiles(_tile_x, _tile_y, _node.tile_x, _node.tile_y, _bounds);
        if (_res.found) {
            array_push(_out_from_temp, { to_node_id: _nid, traversal_cost: _res.cost, kind: "temp", stored_tile_path: _res.path_tiles });
            var _node_key = string(_nid);
            var _list_for_node = is_undefined(_temp_edges_by_from[$ _node_key]) ? [] : _temp_edges_by_from[$ _node_key];
            array_push(_list_for_node, { to_node_id: _temp_node_id, traversal_cost: _res.cost, kind: "temp", stored_tile_path: array_reverse(_res.path_tiles) });
            _temp_edges_by_from[$ _node_key] = _list_for_node;
        }
    }
    _temp_edges_by_from[$ string(_temp_node_id)] = _out_from_temp;
}

// Collect outgoing edges for an abstract node id (includes temp edges, intra edges, inter edges)
function collect_outgoing_edges_for_abstract(_from_node_id, _level_index, _temp_edges_by_from) {
    var _out = [];

    var _from_key = string(_from_node_id);
    if (!is_undefined(_temp_edges_by_from[$ _from_key])) {
        var _temp_list = _temp_edges_by_from[$ _from_key];
        for (var _t = 0; _t < array_length(_temp_list); _t++) array_push(_out, _temp_list[_t]);
    }

    if (_from_node_id >= 0) {
        var _node = global.hpa_all_abstract_nodes[_from_node_id];
        var _cluster = global.hpa_clusters_by_level[_level_index][_node.owner_cluster_id];
        if (is_array(_cluster.intra_edges)) {
            for (var _e = 0; _e < array_length(_cluster.intra_edges); _e++) {
                var _edge = _cluster.intra_edges[_e];
                if (_edge.from_node_id == _from_node_id) array_push(_out, { to_node_id: _edge.to_node_id, traversal_cost: _edge.traversal_cost, kind: "intra", stored_tile_path: _edge.stored_tile_path });
            }
        }
    }

    var _inter = global.hpa_inter_cluster_edges_by_level[_level_index];
    if (is_array(_inter)) {
        for (var _ii = 0; _ii < array_length(_inter); _ii++) {
            var _e2 = _inter[_ii];
            if (_e2.from_node_id == _from_node_id) array_push(_out, { to_node_id: _e2.to_node_id, traversal_cost: _e2.traversal_cost, kind: "inter", stored_tile_path: _e2.stored_tile_path });
        }
    }

    return _out;
}

// -------------------- ABSTRACT SEARCH & REFINEMENT --------------------

// A* on abstract graph, using ds_priority for open set
function abstract_astar_nodes(_start_node_id, _goal_node_id, _level_index, _temp_start_node, _temp_goal_node, _temp_edges_by_from) {
    var _open_pq = ds_priority_create();
    var _came = {};
    var _g_score = {};

    var _start_key = string(_start_node_id);
    _g_score[$ _start_key] = 0;
    ds_priority_add(_open_pq, _start_key, 0);

    var _found = false;

    while (!ds_priority_empty(_open_pq)) {
        var _current_key = ds_priority_delete_min(_open_pq);
        if (is_undefined(_current_key)) break;
        var _current_id = real(_current_key);

        if (_current_id == _goal_node_id) { _found = true; break; }

        var _neighbors = collect_outgoing_edges_for_abstract(_current_id, _level_index, _temp_edges_by_from);
        var _current_g = is_undefined(_g_score[$ _current_key]) ? 0 : _g_score[$ _current_key];

        for (var _n = 0; _n < array_length(_neighbors); _n++) {
            var _edge = _neighbors[_n];
            var _to = _edge.to_node_id;
            var _to_key = string(_to);
            var _tent = _current_g + _edge.traversal_cost;
            if (is_undefined(_g_score[$ _to_key]) || (_tent < _g_score[$ _to_key])) {
                _came[$ _to_key] = _current_key;
                _g_score[$ _to_key] = _tent;
                var _to_xy = get_node_tile_xy(_to, _temp_start_node, _temp_goal_node);
                var _h = abs(_to_xy.x - _temp_goal_node.tile_x) + abs(_to_xy.y - _temp_goal_node.tile_y);
                ds_priority_add(_open_pq, _to_key, _tent + _h);
            }
        }
    }

    ds_priority_destroy(_open_pq);

    if (!_found) return { found: false };

    var _path_nodes = [];
    var _walk = string(_goal_node_id);
    while (_walk != string(_start_node_id)) {
        array_insert(_path_nodes, 0, real(_walk));
        _walk = _came[$ _walk];
    }
    array_insert(_path_nodes, 0, real(string(_start_node_id)));
    return { found: true, path_node_ids: _path_nodes };
}

// Build lookup for all edges on a level (for refinement)
function build_full_edge_lookup_for_level(_level_index) {
    return build_intra_edge_lookup_map_for_level(_level_index);
}

// Refine an abstract node path to a tile-by-tile path
function refine_abstract_path_to_tiles(_path_node_ids, _level_index, _temp_edges_by_from, _temp_start_node, _temp_goal_node) {
    var _tile_path = [];
    var _lookup = build_full_edge_lookup_for_level(_level_index);

    for (var _i = 0; _i < (array_length(_path_node_ids) - 1); _i++) {
        var _from = _path_node_ids[_i];
        var _to = _path_node_ids[_i + 1];
        var _segment_found = false;

        // temp edges?
        var _fromk = string(_from);
        if (!is_undefined(_temp_edges_by_from[$ _fromk])) {
            var _arr = _temp_edges_by_from[$ _fromk];
            for (var _t = 0; _t < array_length(_arr); _t++) {
                var _e = _arr[_t];
                if (_e.to_node_id == _to) {
                    var _seg = _e.stored_tile_path;
                    if (array_length(_tile_path) == 0) {
                        for (var _z = 0; _z < array_length(_seg); _z++) array_push(_tile_path, _seg[_z]);
                    } else {
                        for (var _z = 1; _z < array_length(_seg); _z++) array_push(_tile_path, _seg[_z]);
                    }
                    _segment_found = true;
                    break;
                }
            }
            if (_segment_found) continue;
        }

        var _edge_key = string(_from) + "," + string(_to);
        if (!is_undefined(_lookup[$ _edge_key])) {
            var _stored = _lookup[$ _edge_key];
            if (array_length(_tile_path) == 0) {
                for (var _z = 0; _z < array_length(_stored); _z++) array_push(_tile_path, _stored[_z]);
            } else {
                for (var _z = 1; _z < array_length(_stored); _z++) array_push(_tile_path, _stored[_z]);
            }
            _segment_found = true;
            continue;
        }

        // fallback: single step between neighbor node tiles
        var _fa = get_node_tile_xy(_from, _temp_start_node, _temp_goal_node);
        var _ta = get_node_tile_xy(_to, _temp_start_node, _temp_goal_node);
        var _dx = _ta.x - _fa.x;
        var _dy = _ta.y - _fa.y;
        if (abs(_dx) + abs(_dy) == 1) {
            if (array_length(_tile_path) == 0) {
                array_push(_tile_path, { x: _fa.x, y: _fa.y });
                array_push(_tile_path, { x: _ta.x, y: _ta.y });
            } else {
                array_push(_tile_path, { x: _ta.x, y: _ta.y });
            }
            _segment_found = true;
        }

        if (!_segment_found) {
            show_debug_message("HPA refine: missing segment from " + string(_from) + " to " + string(_to));
        }
    }

    return _tile_path;
}

// -------------------- PUBLIC BUILD & QUERY --------------------

// Build everything (clusters, nodes, inter edges, intra edges) for all levels
function hpa_build_all_levels() {
    hpa_compute_cluster_tile_size_by_level();

    global.hpa_next_abstract_node_id = 0;
    global.hpa_all_abstract_nodes = [];
    global.hpa_inter_cluster_edges_by_level = [];

    global.hpa_clusters_by_level = [];
    for (var _l = 0; _l < global.hpa_levels_total; _l++) hpa_build_clusters_for_level(_l);

    for (var _l = 0; _l < global.hpa_levels_total; _l++) {
        hpa_build_abstract_nodes_and_crossings_for_level(_l);
        build_intra_cluster_edges_for_level(_l);
    }

    show_debug_message("HPA build complete. Levels: " + string(global.hpa_levels_total) + " nodes: " + string(array_length(global.hpa_all_abstract_nodes)));
}

// Find cluster for a tile at a given level
function get_cluster_for_tile(_tile_x, _tile_y, _level_index) {
    var _counts = global.hpa_cluster_grid_counts_by_level[_level_index];
    var _across = _counts.across_x;
    var _down = _counts.down_y;
    var _cluster_tile_size = global.hpa_cluster_tile_size_by_level[_level_index];

    var _max_x = (_across * _cluster_tile_size) - 1;
    var _max_y = (_down * _cluster_tile_size) - 1;
    _tile_x = clamp(_tile_x, 0, _max_x);
    _tile_y = clamp(_tile_y, 0, _max_y);

    var _gx = clamp(floor(_tile_x / _cluster_tile_size), 0, _across - 1);
    var _gy = clamp(floor(_tile_y / _cluster_tile_size), 0, _down - 1);
    var _id = (_gy * _across) + _gx;
    return global.hpa_clusters_by_level[_level_index][_id];
}

// Main query: returns { found, tile_path: [ {x,y}, ... ] }
function hpa_find_path_tiles(_start_tile_x, _start_tile_y, _goal_tile_x, _goal_tile_y, _level_index) {
    _level_index = clamp(_level_index, 0, global.hpa_levels_total - 1);

    var _start_cluster = get_cluster_for_tile(_start_tile_x, _start_tile_y, _level_index);
    var _goal_cluster = get_cluster_for_tile(_goal_tile_x, _goal_tile_y, _level_index);

    // Fast path: both tiles in same cluster -> tile A*
    if (_start_cluster.cluster_id == _goal_cluster.cluster_id) {
        var _direct = astar_within_cluster_tiles(_start_tile_x, _start_tile_y, _goal_tile_x, _goal_tile_y, _start_cluster.bounds);
        if (_direct.found) return { found: true, tile_path: _direct.path_tiles };
    }

    // Create temp start/goal nodes (negative ids)
    var _temp_start_node = { node_id: -1, tile_x: _start_tile_x, tile_y: _start_tile_y };
    var _temp_goal_node  = { node_id: -2, tile_x: _goal_tile_x,  tile_y: _goal_tile_y };

    // temp edges registry (struct keyed by "from_node_id" string -> array of edges)
    var _temp_edges_by_from = {};

    // Connect temp start/goal to their cluster abstract nodes
    make_temp_edges_for_tile_at_level(_start_tile_x, _start_tile_y, _temp_start_node.node_id, _start_cluster, _level_index, _temp_edges_by_from);
    make_temp_edges_for_tile_at_level(_goal_tile_x,  _goal_tile_y,  _temp_goal_node.node_id,  _goal_cluster,  _level_index, _temp_edges_by_from);

    // Abstract A* search
    var _abstract_result = abstract_astar_nodes(_temp_start_node.node_id, _temp_goal_node.node_id, _level_index, _temp_start_node, _temp_goal_node, _temp_edges_by_from);
    if (!_abstract_result.found) return { found: false };

    // Refine to tile path
    var _tile_path = refine_abstract_path_to_tiles(_abstract_result.path_node_ids, _level_index, _temp_edges_by_from, _temp_start_node, _temp_goal_node);
    return { found: (array_length(_tile_path) > 0), tile_path: _tile_path };
}

// -------------------- OPTIONAL: debug draw --------------------

function hpa_debug_draw(_level_index) {
	show_debug_message("_level_index: " + string(_level_index))
	show_debug_message("global.hpa_levels_total: " + string(global.hpa_levels_total))
    _level_index = clamp(_level_index, 0, global.hpa_levels_total - 1);
    var _clusters = global.hpa_clusters_by_level[_level_index];

    draw_set_alpha(0.2);
    draw_set_color(c_aqua);
    for (var _i = 0; _i < array_length(_clusters); _i++) {
        var _cl = _clusters[_i];
        var _b = _cl.bounds;
        draw_rectangle(_b.left_tile * TILE_SIZE_PIXELS, _b.top_tile * TILE_SIZE_PIXELS, _b.right_tile * TILE_SIZE_PIXELS, _b.bottom_tile * TILE_SIZE_PIXELS, false);
    }

    draw_set_alpha(1);
    draw_set_color(c_yellow);
    for (var _i = 0; _i < array_length(_clusters); _i++) {
        var _cl = _clusters[_i];
        for (var _j = 0; _j < array_length(_cl.abstract_nodes); _j++) {
            var _nid = _cl.abstract_nodes[_j];
            var _n = global.hpa_all_abstract_nodes[_nid];
            draw_circle((_n.tile_x + 0.5) * TILE_SIZE_PIXELS, (_n.tile_y + 0.5) * TILE_SIZE_PIXELS, 3, false);
        }
    }

    draw_set_color(c_lime);
    for (var _i = 0; _i < array_length(_clusters); _i++) {
        var _cl = _clusters[_i];
        for (var _e = 0; _e < array_length(_cl.intra_edges); _e++) {
            var _ed = _cl.intra_edges[_e];
            var _na = global.hpa_all_abstract_nodes[_ed.from_node_id];
            var _nb = global.hpa_all_abstract_nodes[_ed.to_node_id];
            draw_line((_na.tile_x + 0.5) * TILE_SIZE_PIXELS, (_na.tile_y + 0.5) * TILE_SIZE_PIXELS, (_nb.tile_x + 0.5) * TILE_SIZE_PIXELS, (_nb.tile_y + 0.5) * TILE_SIZE_PIXELS);
        }
    }

    var _inter = global.hpa_inter_cluster_edges_by_level[_level_index];
    if (is_array(_inter)) {
        draw_set_color(c_red);
        for (var _k = 0; _k < array_length(_inter); _k++) {
            var _ie = _inter[_k];
            var _na = global.hpa_all_abstract_nodes[_ie.from_node_id];
            var _nb = global.hpa_all_abstract_nodes[_ie.to_node_id];
            draw_line((_na.tile_x + 0.5) * TILE_SIZE_PIXELS, (_na.tile_y + 0.5) * TILE_SIZE_PIXELS, (_nb.tile_x + 0.5) * TILE_SIZE_PIXELS, (_nb.tile_y + 0.5) * TILE_SIZE_PIXELS);
        }
    }
}

hpa_build_all_levels();

level = 0;