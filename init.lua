local meters_per_land_node = 500
local height_multiplier = 5
local gravity = 0.165
local sky = "black"
local projection_mode = "orthographic"

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
x = settings:get("gravity")
if x then gravity = tonumber(x) end
x = settings:get("sky")
if x then sky = x end
x = settings:get("projection")
if x then projection_mode = x end

local need_update = false
local world_settings = Settings(minetest.get_worldpath() .. path_separator .. "moon-mapgen-settings.conf")
local x = world_settings:get("land_node_meters")
if x then
	meters_per_land_node=tonumber(x)
else
	world_settings:set("land_node_meters", tostring(meters_per_land_node))
	need_update = true
end
local x = world_settings:get("height_multiplier")
if x then
	height_multiplier=tonumber(x)
else
	world_settings:set("height_multiplier", tostring(height_multiplier))
	need_update = true
end
local x = world_settings:get("projection")
if x then
	projection_mode = x
else
	world_settings:set("projection_mode", projection_mode)
	need_update = true
end
world_settings:write()

local meters_per_vertical_node = meters_per_land_node / height_multiplier
local max_height_units = 255
local radius = 10917000 / 2
local meters_per_degree = 30336.3
local meters_per_height_unit = 77.7246


local nodes_per_height_unit = meters_per_height_unit / meters_per_vertical_node
local max_height_nodes = max_height_units * nodes_per_height_unit
local offsets = {0,0}
local farside_below = -5000
local thickness = 500

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

	local f = assert(ie.io.open(mypath .. "terrain" .. path_separator .. chunk_number .. ".dat.zlib", "rb"))
	chunk = minetest.decompress(f:read("*all"), 'inflate')
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
	return get_interpolated_data(longitude,latitude) * nodes_per_height_unit
end

local orthographic = {
	get_longitude_latitude = function(x,z,farside)
		local x = x * meters_per_land_node / radius
		local z = z * meters_per_land_node / radius
		local xz2 = x*x + z*z
		if xz2 > 1 then
			return nil
		end
		local longitude = math.atan2(x,math.sqrt(1-xz2))
		if farside then
			longitude = longitude + math.pi
			if longitude > math.pi then
				longitude = longitude - 2 * math.pi
			end
		end
		return longitude, math.asin(z)
	end,

	get_xz_from_longitude_latitude = function(longitude, latitude)
		local z = math.sin(latitude) * radius / meters_per_land_node
		local x = math.cos(latitude) * math.sin(longitude) * radius / meters_per_land_node
		return x,z
	end
}

-- TODO: add equal distance projection
local projection = orthographic

local function height(x,z,farside)
	-- assume z goes north and x goes east
    local longitude,latitude = projection.get_longitude_latitude(x,z,farside)
    if not longitude then return nil end
	return height_by_longitude_latitude(longitude, latitude)
end

offsets[0] = -height(0,0)
offsets[1] = farside_below - max_height_nodes

minetest.set_mapgen_params({mgname="singlenode", water_level = -30000}) -- flags="nolight", flagmask="nolight"

minetest.register_on_generated(function(minp, maxp, seed)
	local c_air = minetest.get_content_id("air")
	local c_stone = minetest.get_content_id("default:stone")
	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	local data = vm:get_data()
	local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}

	if minp.y > max_height_nodes then
		for pos in area:iterp(minp,maxp) do
			data[pos] = c_air
		end
	else
		local offset
		local farside
		if minp.y <= farside_below then
			-- we assume the chunk we're generating never spans between far to nearside
			offset = offsets[1]
			farside = true
		else
			offset = offsets[0]
			farside = false
		end
		for x = minp.x,maxp.x do
			for z = minp.z,maxp.z do
				local f = height(x,z,farside)
				if not f then
    				for y = minp.y,maxp.y do
    					data[area:index(x, y, z)] = c_air
    				end
				else
    				f = math.floor(f + offset)					
    				for y = minp.y,maxp.y do
						if y < offset - thickness or y > f then 
							data[area:index(x, y, z)] = c_air
						elseif y <= f then
							data[area:index(x, y, z)] = c_stone
						end
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
			local side = 0
			local latitude, longitude = args:match("^([-0-9.]+) ([-0-9.]+)")
			if longitude then
				latitude = tonumber(latitude) * math.pi / 180
				longitude = tonumber(longitude)
				if longitude < -90 or longitude > 90 then
					side = 1
				end
				longitude = longitude * math.pi / 180
			else
				latitude,longitude = find_feature(args)
				if not latitude then
					minetest.chat_send_player(name, "Cannot find crater "..args)
					return
				end
				if longitude < half_pi or longitude > half_pi then
					side = 1
				end
			end
			if latitude < -half_pi or latitude > half_pi or longitude < -math.pi or longitude > math.pi then
                minetest.chat_send_player(name, "Out of range.")
				return
			end
			local x,z = projection.get_xz_from_longitude_latitude(longitude,latitude)
			local y = height(x,z,side == 1) + offsets[side]			
			minetest.log("action", "jumping to "..x.." "..y.." "..z)
		    minetest.get_player_by_name(name):setpos({x=x,y=y,z=z})
		end
	end})

minetest.register_chatcommand("where",
	{params="" ,
	description="Get latitude and longitude of current position on moon.",
	func = function(name, args)
	        local pos = minetest.get_player_by_name(name):getpos()
			local farside = pos.y < farside_below + thickness
            local longitude,latitude = projection.get_longitude_latitude(pos.x, pos.z, farside)
			if longitude then
                minetest.chat_send_player(name, "Latitude: "..(latitude*180/math.pi)..", longitude: "..(longitude*180/math.pi))
			else
                minetest.chat_send_player(name, "Out of range.")
			end
	end})

minetest.register_on_joinplayer(function(player)
	local override = player:get_physics_override()
	override['gravity'] = gravity
	player:set_physics_override(override)
	 -- texture order: up,down,east,west,south,north
	if sky == "black" then
		player:set_sky({r=0,g=0,b=0},'plain')
	elseif sky == "fancy" then
		player:set_sky({r=0,g=0,b=0},'skybox',
			{'sky_pos_y.png','sky_neg_y.png','sky_neg_z.png','sky_pos_z.png','sky_neg_x.png','sky_pos_x.png'})
	end
end)
