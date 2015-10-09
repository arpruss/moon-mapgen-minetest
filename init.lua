local meters_per_land_node = 500
local height_multiplier = 5

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

local settings = Settings(mypath .. "settings.conf")
local x = settings:get("land_node_meters")
if x then meters_per_land_node = tonumber(x) end
x = settings:get("height_multiplier")
if x then height_multiplier = tonumber(x) end

local meters_per_vertical_node = meters_per_land_node / height_multiplier
local max_height_units = 255
local radius = 10917000 / 2
local meters_per_degree = 30336.3
local meters_per_height_unit = 77.7246

local nodes_per_height_unit = meters_per_height_unit / meters_per_vertical_node
local max_height = 0
local min_height = 0

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

local function height_by_longitude_latitude(longitude, latitude)
	return get_interpolated_data(longitude,latitude) * nodes_per_height_unit + min_height
end

local function get_longitude_latitude(x,z)
	local x = x * meters_per_land_node / radius
	local z = z * meters_per_land_node / radius
	local xz2 = x*x + z*z
	if xz2 > 1 then
		return nil
	end
	return math.atan2(x,math.sqrt(1-xz2)), math.asin(z)
end


local function height(x,z)
	-- assume z goes north and x goes east
        local longitude,latitude = get_longitude_latitude(x,z)
        if not longitude then return nil end
	return height_by_longitude_latitude(longitude, latitude)
end

min_height = -height(0,0)
max_height = max_height_units * nodes_per_height_unit + min_height

minetest.set_mapgen_params({mgname="singlenode", water_level = -30000}) -- flags="nolight", flagmask="nolight"

minetest.register_on_generated(function(minp, maxp, seed)
	local c_air = minetest.get_content_id("air")
	local c_stone = minetest.get_content_id("default:stone")
	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	local data = vm:get_data()
	local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
	
	if minp.y > max_height then
		for pos in area:iterp(minp,maxp) do
			data[pos] = c_air
		end
	else
		for x = minp.x,maxp.x do
			for z = minp.z,maxp.z do
				local f = height(x,z)
				if not f then
    				for y = minp.y,maxp.y do
    					data[area:index(x, y, z)] = c_air
    				end
				else
    				f = math.floor(f)
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
end)

local function find_feature(name)
    local lower_name = name:lower():gsub("[-' ]", "")
    local f = assert(ie.io.open(mypath .. "craters.txt", "r"))
    while true do
       local line = f:read()
       if not line then break end
       local n,lat,ns,lon,ew = line:match("^([-A-Za-z ]*[A-Za-z]) +([0-9.]+)([NS]) +([0-9.]+)([EW])")
	   if n and n:lower():gsub("[-' ]", "") == lower_name then
		   if ns == 'S' then
			  lat = -math.pi * tonumber(lat) / 180
		   else
			  lat = math.pi * tonumber(lat) / 180
		   end
		   if ew == 'W' then
			  lon = -math.pi * tonumber(lon) / 180
		   else
			  lon = math.pi * tonumber(lon) / 180
		   end
		   return lat,lon
		end
    end
    return nil
end

minetest.register_chatcommand("goto",
	{params="<latitude> <longitude>  or  <crater name>" ,
	description="Go to location on moon. Negative latitudes are south and negative longitudes are west.",
	func = function(name, args)
		if args ~= "" then
			local latitude, longitude = args:match("^([-0-9.]+) ([-0-9.]+)")
			if longitude then
				latitude = tonumber(latitude) * math.pi / 180
				longitude = tonumber(longitude) * math.pi / 180
			else
				latitude,longitude = find_feature(args)
				if not latitude then
					minetest.chat_send_player(name, "Cannot find crater "..args)
					return
				end
			end
			if latitude < -math.pi / 2 or latitude > math.pi / 2 or longitude < -math.pi /2 or longitude > math.pi / 2 then
                                minetest.chat_send_player(name, "Not on near side")
				return
			end
			local z = math.sin(latitude) * radius / meters_per_land_node
			local x = math.cos(latitude) * math.sin(longitude) * radius / meters_per_land_node
			local h = height_by_longitude_latitude(longitude,latitude)
			minetest.log("action", "jumping to "..x.." "..h.." "..z)
		        minetest.get_player_by_name(name):setpos({x=x,y=h,z=z})
		end
	end})

minetest.register_chatcommand("where",
	{params="" ,
	description="Get latitude and longitude of current position on moon.",
	func = function(name, args)
	        local pos = minetest.get_player_by_name(name):getpos()
                local longitude,latitude = get_longitude_latitude(pos.x, pos.z)
                minetest.chat_send_player(name, "Latitude: "..(latitude*180/math.pi)..", longitude: "..(longitude*180/math.pi))
	end})
