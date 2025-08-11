// Script assets have changed for v2.3.0 see
// https://help.yoyogames.com/hc/en-us/articles/360005277377 for more information
function loop_current_hierarchy_level(){
	if (current_hierarchy_level < 0) current_hierarchy_level = hierarchy_levels - 1;
	if (current_hierarchy_level >= hierarchy_levels) current_hierarchy_level = 0;
}