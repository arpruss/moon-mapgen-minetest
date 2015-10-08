if minetest.request_insecure_environment then
   ie = minetest.request_insecure_environment()
else
   ie = _G
end

local source = ie.debug.getinfo(1).source:sub(2)
-- Detect windows via backslashes in paths
local mypath = minetest.get_modpath(minetest.get_current_modname())
local is_windows = (nil ~= string.find(ie.package.path..ie.package.cpath..source..mypath, "%\\%?"))
local path_separator
if is_windows then
   path_separator = "\\"
else
   path_separator = "/"
end
mypath = mypath .. path_separator

local chunks = {}
local data_per_degree = 64
local stripe_size = 360 * data_per_degree

local function get_raw_data(latitude,longitude)
	stripe = 90*data_per_degree - latitude
	if stripe < 0 then
		stripe = 0
	elseif stripe > 90*data_per_degree then 
		stripe = 90*chunk_resolution - 1
	end
	local chunk_number = math.floor(stripe / (5 * chunk_resolution))
	longitude = longitude + 180 * data_per_degree
	if longitude < 0
	local chunk_offset = (stripe - chunk_number * (5 * chunk_resolution)) * stripe_size)
end


local function height(x,z)
	return 25 * math.cos(math.hypot(x,z) * math.pi / 50)
end

local max_height = 25
local min_height = -25

minetest.register_on_generated(function(minp, maxp, seed)
	local c_air = minetest.get_content_id("air")
	local c_stone = minetest.get_content_id("default:stone")
	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	local data = vm:get_data()
	local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
	local cached_height

	if minp.y > max_height then
	        cached_height = function(x,z)
	                return max_height
	        end

		for pos in area:iterp(minp,maxp) do
			data[pos] = c_air
		end
	elseif maxp.y < min_height then
	        cached_height = function(x,z)
	                return maxp.y
	        end

		for pos in area:iterp(minp,maxp) do
			data[pos] = c_stone
		end
	else
	        local height_cache = {}
	        
	        cached_height = function(x,z)
                        return height_cache[x][z]
	        end

		for x = minp.x,maxp.x do
		        height_cache[x] = {}
			for z = minp.z,maxp.z do
				local f = math.floor(height(x,z))
				height_cache[x][z] = f
				for y = minp.y,f do
					data[area:index(x, y, z)] = c_stone
				end
				for y = f+1,maxp.y do
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
		local x = math.floor(1+pos.x)
		local z = math.floor(1+pos.z)
		if minp.x <= x and x <= maxp.x and minp.y <= pos.y and pos.y <= maxp.y and
			minp.z <= z and z <= maxp.z then

			local h = cached_height(x,z)
			if pos.y < h then
				pos.y = h
				players[i]:setpos(pos)
			end
		end
	end
end)
