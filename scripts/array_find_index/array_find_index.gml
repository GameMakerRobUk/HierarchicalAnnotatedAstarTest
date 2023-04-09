function array_find_index(_array, _value){
	for (var i = 0; i < array_length(_array); i ++){
		if (_array[i] == _value) return i;
	}	
	
	return -1;
}