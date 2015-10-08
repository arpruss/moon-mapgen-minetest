local central_latitude_degrees = 0
local central_longitude_degrees = 0
local meters_per_node_horizontal = 500 -- 360 degrees is 21842 nodes
local meters_per_node_vertical = 100 -- max height is 199 nodes

local max_height_units = 255
local meters_per_degree = 30336.3
local meters_per_height_unit = 77.7246

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
local row_size = 360 * data_per_degree
local rows_per_hemisphere = 90 * data_per_degree
local rows_total = 180 * data_per_degree
local rows_per_chunk = 5 * data_per_degree
local columns_per_hemisphere = 180 * data_per_degree
local columns_total = 360 * data_per_degree
local half_pi = math.pi / 2
local radians_to_pixels = 180 * data_per_degree / math.pi

local function get_chunk(chunk_number)
	local chunk = chunks[chunk_number]

	if chunk then
		return chunk
	end

	local f = assert(ie.io.open(mypath .. "terrain" .. path_separator .. chunk_number .. ".dat", "rb"))
	chunk = f:read("*all")
	f:close()
	chunks[chunk_number] = chunk
	return chunk
end

local function get_raw_data(column,row)
        if row < 0 then
           row = 0
        elseif row >= rows_total then
           row = rows_total - 1
        end
        if column < 0 then
           column = 0
        elseif column >= columns_total then
           column = columns_total - 1
        end
	local chunk_number = math.floor(row / rows_per_chunk)
	local offset = (row - chunk_number * rows_per_chunk) * row_size + column
	return get_chunk(chunk_number):byte(offset+1) -- correct for lua strings starting at index 1
end

local function get_interpolated_data(longitude,latitude)
    local row = (half_pi - latitude) * radians_to_pixels
    local column = (longitude + math.pi) * radians_to_pixels
    local row0 = math.floor(row)
    local drow = row - row0
    local column0 = math.floor(column)
    local dcolumn = column - column0
    local v00 = get_raw_data(column0,row0)
    local v10 = get_raw_data(column0+1,row0)
    local v01 = get_raw_data(column0,row0+1)
    local v11 = get_raw_data(column0+1,row0+1)
    local v0 = v00 * (1-dcolumn) + v10 * dcolumn
    local v1 = v01 * (1-dcolumn) + v11 * dcolumn
    return v0 * (1-drow) + v1 * drow
end

local function height(x,z)
      return 25 * math.cos(math.hypot(x,z) * math.pi / 50)
end

local max_height = math.ceil(max_height_units * meters_per_height_unit / meters_per_node_vertical)
local min_height = 0

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
				local f = height(x,z)
				if not f then 
					height_cache[x][z] = minp.y
    				for y = minp.y,maxp.y do
    					data[area:index(x, y, z)] = c_air
    				end
				else
    				f = math.floor(f)
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


