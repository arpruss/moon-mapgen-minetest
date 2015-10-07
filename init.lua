local function height(x,z)
	return 25 * math.cos(math.hypot(x,z) * math.pi / 50)
end

minetest.register_on_generated(function(minp, maxp, seed)
	local c_air = minetest.get_content_id("air")
	local c_stone = minetest.get_content_id("default:stone")
	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	local data = vm:get_data()
	local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}

	if minp.y > 25 then
		for pos in area:iterp(minp,maxp) do
			data[pos] = c_air
		end
	elseif maxp.y < -25 then
		for pos in area:iterp(minp,maxp) do
			data[pos] = c_stone
		end
	else
		for x = minp.x,maxp.x do
			for z = minp.z,maxp.z do
				local f = height(x,z)
				for y = minp.y,math.floor(f) do
					data[area:index(x, y, z)] = c_stone
				end
				for y = math.floor(f)+1,maxp.y do
					data[area:index(x, y, z)] = c_air
				end
			end
		end
	end
 
	vm:set_data(data)
	vm:calc_lighting()
	vm:update_liquids()
	vm:write_to_map()

	-- ensure player isn't underground (no caves on this mapgen)
	local players = minetest.get_connected_players()
	for i = 1,#players do
		local pos = players[i]:getpos()
		if minp.x <= pos.x and pos.x <= maxp.x and minp.y <= pos.y and pos.y <= maxp.y and
			minp.z <= pos.z and pos.z <= maxp.z then
			local x = math.floor(1+pos.x)
			local z = math.floor(1+pos.z)
			local h = math.floor(height(x,z))+1
			if pos.y < h then
				pos.y = h
				players[i]:setpos(pos)
			end
		end
	end
end)
