--[[
LICENSE FOR CODE (NOT FOR TEXTURES)

The MIT License (MIT)

Code copyright (c) 2015 Alexander R. Pruss

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE. 
--]]

if minetest.request_insecure_environment then
   ie = minetest.request_insecure_environment()
else
   ie = _G
end

local meters_per_land_node = 150
local height_multiplier = 1
local gravity = 0.165
local sky = "black"
local projection_mode = "equaldistance"
local teleport = false


	
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
x = settings:get_bool("teleport")
if x ~= nil then teleport = x end

local need_update = false
local world_settings = Settings(minetest.get_worldpath() .. path_separator .. "moon-mapgen-settings.conf")
local x = world_settings:get("projection")
if x then
	projection_mode = x
else
	world_settings:set("projection_mode", projection_mode)
	need_update = true
end
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
local x = world_settings:get_bool("teleport")
if x ~= nil then
	teleport=x
else
	world_settings:set("teleport", tostring(teleport))
	need_update = true
end
world_settings:write()

minetest.set_mapgen_params({mgname="singlenode", water_level = -30000}) -- flags="nolight", flagmask="nolight"
local projection

local meters_per_vertical_node = meters_per_land_node / height_multiplier
local max_height_units = 255
local radius = 1738000
local meters_per_degree = 30336.3
local meters_per_height_unit = 77.7246
local inner_radius = 1737400

local nodes_per_height_unit = meters_per_height_unit / meters_per_vertical_node
local max_height_nodes = max_height_units * nodes_per_height_unit
local land_normalize = meters_per_land_node / radius

local radius_nodes = radius / meters_per_land_node
local inner_radius_nodes = inner_radius / meters_per_land_node
local outer_radius_nodes = inner_radius_nodes + max_height_nodes

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
           column = columns_total - 1
        elseif column >= columns_total then
           column = 0
        end
	local chunk_number = math.floor(row / rows_per_chunk)
	local offset = (row - chunk_number * rows_per_chunk) * row_size + column
	return get_chunk(chunk_number):byte(offset+1) -- correct for lua strings starting at index 1
end

local function get_interpolated_data(longitude,latitude)
    local row = (half_pi - latitude) * radians_to_pixels
	if longitude < 0 then longitude = longitude + 2 * math.pi end
    local column = longitude * radians_to_pixels
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


local moonstone = {}

for i = 0,255 do
	local name = "moon:moonstone_"..i
	minetest.register_node(name, {
		description = "Moon stone "..i,
		tiles = {"block"..i..".png"},
		groups = {cracky=3, stone=1},
		drop = 'moon:moonstone_'..i,
		legacy_mineral = true,
	})
	moonstone[i] = minetest.get_content_id(name)
end

local albedo_width = 4096
local albedo_height = 2048
local albedo_filename = "albedo4096x2048.dat"
local albedo_radians_to_pixels = albedo_height / math.pi

local f = assert(ie.io.open(mypath .. albedo_filename, "rb"))
local albedo = f:read("*all")
f:close()
local function get_raw_albedo(column,row)
	if row < 0 then
	   row = 0
	elseif row >= albedo_height then
	   row = albedo_height - 1
	end
	if column < 0 then
	   column = 0
	elseif column >= albedo_width then
	   column = albedo_width - 1
	end
	return albedo:byte(row * albedo_width + column)
end

local function get_interpolated_albedo(longitude,latitude)
    local row = (half_pi - latitude) * albedo_radians_to_pixels
	if longitude < 0 then longitude = longitude + 2 * math.pi end
    local column = longitude * albedo_radians_to_pixels
    local row0 = math.floor(row)
    local drow = row - row0
    local column0 = math.floor(column)
    local dcolumn = column - column0
    local v00 = get_raw_albedo(column0,row0)
    local v10 = get_raw_albedo(column0+1,row0)
    local v01 = get_raw_albedo(column0,row0+1)
    local v11 = get_raw_albedo(column0+1,row0+1)
    local v0 = v00 * (1-dcolumn) + v10 * dcolumn
    local v1 = v01 * (1-dcolumn) + v11 * dcolumn
    local albedo = v0 * (1-drow) + v1 * drow
	return math.floor(albedo)
end



local equaldistance

local orthographic = {
	get_longitude_latitude = function(x,y0,z,farside,allow_oversize)
		local x = x * land_normalize
		local z = z * land_normalize
		local xz2 = x*x + z*z
		if xz2 > 1 then
			if allow_oversize then
				local r = math.sqrt(xz2)
				x = x / r
				z = z / r
			else
				return nil
			end
		end
		local y = math.sqrt(1-xz2)
		local longitude
		if y < 1e-8 and math.abs(x) < 1e-8 then
			longitude = 0
		else
			longitude = math.atan2(x,y)
		end
		if farside then
			longitude = longitude + math.pi
			if longitude > math.pi then
				longitude = longitude - 2 * math.pi
			end
		end
		return longitude, math.asin(z)
	end,

	get_xz_from_longitude_latitude = function(longitude, latitude)
		local z = math.sin(latitude) / land_normalize
		if longitude < -half_pi or longitude > half_pi then
			longitude = longitude - math.pi
		end
		local x = math.cos(latitude) * math.sin(longitude) / land_normalize
		return x,z
	end,

	goto_latitude_longitude_degrees = function(name, latitude, longitude, feature_name)
		local side =  0
		latitude = tonumber(latitude) * math.pi / 180
		longitude = tonumber(longitude)
		if longitude < -90 or longitude > 90 then
			side = 1
		end
		longitude = longitude * math.pi / 180
		if latitude < -half_pi or latitude > half_pi or longitude < -math.pi or longitude > math.pi then
			minetest.chat_send_player(name, "Out of range.")
			return
		end
		local x,z = projection.get_xz_from_longitude_latitude(longitude,latitude)
		local y = height_by_longitude_latitude(longitude, latitude) + offsets[side]			
		if feature_name then
			minetest.chat_send_player(name, "Jumping to "..feature_name..".")
			minetest.log("action", "jumping to "..feature_name.." at "..x.." "..y.." "..z)
		else
			minetest.log("action", "jumping to "..x.." "..y.." "..z)
		end
		minetest.get_player_by_name(name):setpos({x=x,y=y,z=z})
	end,
	
	generate = function(minp, maxp, data, area, vacuum, stone)
		if minp.y > max_height_nodes then
			for pos in area:iterp(minp,maxp) do
				data[pos] = vacuum
			end
		else
			local offset, farside
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
					local longitude,latitude = projection.get_longitude_latitude(x,0,z,farside,teleport and projection==equaldistance)
					if not longitude then
						for y = minp.y,maxp.y do
							data[area:index(x, y, z)] = vacuum
						end
					else
						local f = math.floor(height_by_longitude_latitude(longitude, latitude) + offset)
						local block = moonstone[get_interpolated_albedo(longitude,latitude)]
						for y = minp.y,maxp.y do
							if y < offset - thickness or y > f then 
								data[area:index(x, y, z)] = vacuum
							elseif y <= f then
								data[area:index(x, y, z)] = block
							end
						end
					end
				end
			end
		end
	end

}

equaldistance = {
	get_longitude_latitude = function(x,y0,z,farside,allow_oversize)
		local x = x * land_normalize
		local z = z * land_normalize
		local xz2 = x*x + z*z

		if xz2 > 2 or (xz2 > 1 and not allow_oversize) then
			return nil
		end
		
		local xz = math.sqrt(xz2)
		
		if xz < 1e-8 then
			if farside then
				return 0,math.pi
			else
				return 0,0
			end
		end

		local adjustment = math.sin(xz*half_pi)/xz
		x = x * adjustment
		z = z * adjustment

		local y = math.sqrt(1-x*x-z*z)

		local longitude = math.atan2(x,y)
		if farside then
			longitude = longitude + math.pi
			if longitude > math.pi then
				longitude = longitude - 2 * math.pi
			end
		end

		if xz > 1 then
			if longitude >= 0 then 
				longitude = math.pi - longitude
			else 
				longitude = -math.pi - longitude
			end
		end
		
		return longitude, math.asin(z)
	end,
	
	get_xz_from_longitude_latitude = function(longitude, latitude)
		local z = math.sin(latitude)
		if longitude < -half_pi or longitude > half_pi then
			longitude = longitude - math.pi
		end
		local x = math.cos(latitude) * math.sin(longitude)
		
		local xz = math.sqrt(x*x + z*z)
		
		if xz < 1e-8 then
			return x/land_normalize,z/land_normalize
		end
		
		local adjustment = math.asin(xz)/half_pi/xz
		
		return x * adjustment / land_normalize, z * adjustment / land_normalize
	end,

	goto_latitude_longitude_degrees = orthographic.goto_latitude_longitude_degrees,
	
	generate = orthographic.generate
}

local sphere = {
	get_longitude_latitude = function(x,y,z,farside)
		local r = math.sqrt(x*x+y*y+z*z)

		if r < 1e-8 then
			return 0,0
		end

		local latitude = math.asin(z/r)
		local longitude = math.atan2(x,y)
		
		return longitude, latitude
	end,

	in_moon = function(x,y,z)
		local r = math.sqrt(x*x+y*y+z*z)
		
		if r < inner_radius_nodes then
			return true
		elseif outer_radius_nodes < r then
			return false
		end
		
		x = x / r
		y = y / r
		z = z / r
		
		local latitude = math.asin(z)
		local longitude = math.atan2(x,y)

		return r <= inner_radius_nodes + height_by_longitude_latitude(longitude, latitude)
	end,


	generate = function(minp, maxp, data, area, vacuum, stone)
		local block_radius = vector.distance(minp, maxp) / 2
		local r = vector.length(vector.multiply(vector.add(minp,maxp), 0.5))

		if r + block_radius < inner_radius_nodes then
			for pos in area:iterp(minp,maxp) do
				data[pos] = stone
			end
		elseif outer_radius_nodes < r - block_radius then
			for pos in area:iterp(minp,maxp) do
				data[pos] = vacuum
			end
		else
			for y = minp.y,maxp.y do
				for x = minp.x,maxp.x do
					for z = minp.z,maxp.z do
						if projection.in_moon(x,y,z) then
							data[area:index(x,y,z)] = stone
						else
							data[area:index(x,y,z)] = vacuum
						end
					end
				end
			end
		end		
	end,
	
	goto_latitude_longitude_degrees = function(name, latitude, longitude, feature_name)
		latitude = latitude * math.pi / 180
		longitude = longitude * math.pi / 180
		local x = math.cos(latitude) * math.sin(longitude)
		local y = math.cos(latitude) * math.cos(longitude)
		local z = math.sin(latitude)
		local r = inner_radius_nodes + height_by_longitude_latitude(longitude, latitude)
		x = x * r
		y = y * r
		z = z * r
		local player = minetest.get_player_by_name(name)
		if y < 0 then 
			y = y - 2
		end

		if feature_name then
			minetest.chat_send_player(name, "Jumping to "..feature_name..".")
			minetest.log("action", "jumping to "..feature_name.." at "..x.." "..y.." "..z)
		else
			minetest.chat_send_player(name, "Jumping to coordinates.")
			minetest.log("action", "jumping to "..x.." "..y.." "..z)
		end
		player:setpos({x=x,y=y,z=z})
	end
}

minetest.log("action", "Moon projection mode: "..projection_mode)

if projection_mode == "sphere" then
	projection = sphere
	
else
	if projection_mode == "equaldistance" then
		projection = equaldistance
	else 
		projection = orthographic
	end
	
	offsets[0] = -height_by_longitude_latitude(0,0)
	offsets[1] = farside_below - max_height_nodes
end

minetest.register_on_generated(function(minp, maxp, seed)
	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	local data = vm:get_data()
	local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}

	projection.generate(minp, maxp, data, area,  minetest.get_content_id("air"),
		minetest.get_content_id("default:stone"))
	
	vm:set_data(data)
	vm:calc_lighting()
	vm:update_liquids()
	vm:write_to_map()
end)

		
local function find_feature(name)
    local lower_name = name:lower():gsub("[^A-Za-z]", "")
	local name_length = lower_name:len()
    local f = assert(ie.io.open(mypath .. "features.txt", "r"))
	local partial_fullname,partial_lat,partial_lon,partial_size
	partial_lat = nil
    while true do
	    local line = f:read()
	    if not line then break end
	    local key,fullname,lat,lon,size = line:match("^([^|]+)%|([^|]+)%|([^|]+)%|([^|]+)%|([^|]+)")
	    if key == lower_name then
		   f.close()
		   return tonumber(lat),tonumber(lon),fullname
		end
		if not partial_lat and key:sub(1,name_length) == lower_name then
			partial_fullname,partial_lat,partial_lon,partial_size = fullname,lat,lon,size
		end
    end
	f.close()
	if partial_lat then
		return tonumber(partial_lat),tonumber(partial_lon),partial_fullname
	else
		return nil
	end
end

minetest.register_chatcommand("goto",
	{params="<latitude> <longitude>  or  <feature name>" ,
	description="Go to location on moon. Negative latitudes are south and negative longitudes are west.",
	func = function(name, args)
		if args ~= "" then
			local side = 0
			local latitude, longitude = args:match("^([-0-9.]+) ([-0-9.]+)")
			local feature_name = nil
			if not longitude then
				latitude,longitude,feature_name = find_feature(args)
				if not latitude then
					minetest.chat_send_player(name, "Cannot find object "..args)
					return
				end
			end
			projection.goto_latitude_longitude_degrees(name,latitude,longitude,feature_name)
		end
	end})

minetest.register_chatcommand("where",
	{params="" ,
	description="Get latitude and longitude of current position on moon.",
	func = function(name, args)
	        local pos = minetest.get_player_by_name(name):getpos()
			local farside = pos.y < farside_below + thickness -- irrelevant if sphere
            local longitude,latitude = projection.get_longitude_latitude(pos.x, pos.y, pos.z, farside)
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
	local name = player:get_player_name()
	local p = minetest.get_player_privs(name)
	p['fly'] = true
	minetest.set_player_privs(name, p)
end)

if projection == sphere then
	local default_location = function(player) 
		player:setpos({x=0, y=inner_radius_nodes+height_by_longitude_latitude(0,0), z=0})
	end

	minetest.register_on_newplayer(default_location)
	minetest.register_on_respawnplayer(default_location)
end

if teleport and projection ~= sphere then
	minetest.register_globalstep(function(dtime)
		local players = minetest.get_connected_players()
		for i = 1,#players do
			local pos = players[i]:getpos()
			local r = math.hypot(pos.x, pos.z)
			if r > radius_nodes then
				local farside = pos.y <= farside_below
				local longitude,latitude = 
					projection.get_longitude_latitude(
					pos.x,pos.y,pos.z,farside,true)
				if longitude then
					local name = players[i]:get_player_name()
					minetest.chat_send_player(name, 
						"Teleporting to other side, latitude: "..(latitude*180/math.pi)..", longitude: "..(longitude*180/math.pi))
					projection.goto_latitude_longitude_degrees(name, 
						latitude * 180 / math.pi, longitude * 180 / math.pi)
				end
			end
		end
	end)
end
