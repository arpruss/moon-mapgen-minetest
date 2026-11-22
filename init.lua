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

local atan2 = math.atan2 or math.atan
local hypot = math.hypot or function(x, y)
	return math.sqrt(x * x + y * y)
end

local modname = core.get_current_modname()
local path_separator = DIR_DELIM or "/"
local mypath = core.get_modpath(modname) .. path_separator

-- Defaults (matching settings.conf and settingtypes.txt)
local meters_per_land_node = 150
local height_multiplier = 1
local gravity = 0.165
local sky = "fancy"
local projection_mode = "equaldistance"
local teleport = true
local use_albedo = true

local function parse_positive_number(val, fallback)
	local n = tonumber(val)
	if n and n > 0 then
		return n
	end
	return fallback
end

-- 1. Load bundled settings.conf (for backwards compatibility)
local mod_settings = Settings(mypath .. "settings.conf")
do
	local v = mod_settings:get("land_node_meters")
	if v then meters_per_land_node = parse_positive_number(v, meters_per_land_node) end
	v = mod_settings:get("height_multiplier")
	if v then height_multiplier = parse_positive_number(v, height_multiplier) end
	v = mod_settings:get("gravity")
	if v then gravity = parse_positive_number(v, gravity) end
	v = mod_settings:get("sky")
	if v then sky = v end
	v = mod_settings:get("projection")
	if v then projection_mode = v end
	v = mod_settings:get_bool("teleport")
	if v ~= nil then teleport = v end
	v = mod_settings:get_bool("albedo")
	if v ~= nil then use_albedo = v end
end

-- 2. Apply Luanti global settings (settingtypes.txt / minetest.conf) if explicitly set
do
	local v = core.settings:get("moon_mapgen_land_node_meters")
	if v then meters_per_land_node = parse_positive_number(v, meters_per_land_node) end
	v = core.settings:get("moon_mapgen_height_multiplier")
	if v then height_multiplier = parse_positive_number(v, height_multiplier) end
	v = core.settings:get("moon_mapgen_gravity")
	if v then gravity = parse_positive_number(v, gravity) end
	v = core.settings:get("moon_mapgen_sky")
	if v then sky = v end
	v = core.settings:get("moon_mapgen_projection")
	if v then projection_mode = v end
	v = core.settings:get_bool("moon_mapgen_teleport")
	if v ~= nil then teleport = v end
	v = core.settings:get_bool("moon_mapgen_albedo")
	if v ~= nil then use_albedo = v end
end

-- 3. Load/save per-world settings so terrain geometry stays consistent for existing worlds
local need_update = false
local world_settings = Settings(core.get_worldpath() .. path_separator .. "moon-mapgen-settings.conf")
do
	local v = world_settings:get("projection_mode") or world_settings:get("projection")
	if v then
		projection_mode = v
	else
		world_settings:set("projection_mode", projection_mode)
		need_update = true
	end

	v = world_settings:get("land_node_meters")
	if v then
		meters_per_land_node = parse_positive_number(v, meters_per_land_node)
	else
		world_settings:set("land_node_meters", tostring(meters_per_land_node))
		need_update = true
	end

	v = world_settings:get("height_multiplier")
	if v then
		height_multiplier = parse_positive_number(v, height_multiplier)
	else
		world_settings:set("height_multiplier", tostring(height_multiplier))
		need_update = true
	end

	v = world_settings:get_bool("teleport")
	if v ~= nil then
		teleport = v
	else
		world_settings:set("teleport", tostring(teleport))
		need_update = true
	end

	v = world_settings:get_bool("albedo")
	if v ~= nil then
		use_albedo = v
	else
		world_settings:set("albedo", tostring(use_albedo))
		need_update = true
	end

	if need_update then
		core.log("action", "[" .. modname .. "] Saving world-specific settings.")
		world_settings:write()
	end
end

-- Force singlenode mapgen so default engine mapgens do not interfere
core.set_mapgen_setting("mg_name", "singlenode", true)
core.set_mapgen_setting("water_level", "-30000", true)

local projection

local meters_per_vertical_node = meters_per_land_node / height_multiplier
local max_height_units = 255
local radius = 1738000
local meters_per_height_unit = 77.7246
local inner_radius = 1737400

local nodes_per_height_unit = meters_per_height_unit / meters_per_vertical_node
local max_height_nodes = max_height_units * nodes_per_height_unit
local land_normalize = meters_per_land_node / radius

local radius_nodes = radius / meters_per_land_node
local inner_radius_nodes = inner_radius / meters_per_land_node
local outer_radius_nodes = inner_radius_nodes + max_height_nodes

local offsets = { [0] = 0, [1] = 0 }
local farside_below = -5000
local thickness = 500
local farside_threshold = -2500

local data_per_degree = 64
local row_size = 360 * data_per_degree
local rows_total = 180 * data_per_degree
local rows_per_chunk = 5 * data_per_degree
local num_chunks = rows_total / rows_per_chunk -- 36
local columns_total = 360 * data_per_degree
local half_pi = math.pi / 2
local two_pi = 2 * math.pi
local radians_to_pixels = 180 * data_per_degree / math.pi

-- Preload compressed terrain chunks at load time (sandbox-safe; no runtime modpath I/O needed)
local compressed_chunks = {}
for i = 0, num_chunks - 1 do
	local chunk_path = mypath .. "terrain" .. path_separator .. i .. ".dat.zlib"
	local f = assert(io.open(chunk_path, "rb"), "Failed to open terrain chunk: " .. chunk_path)
	compressed_chunks[i] = f:read("*a")
	f:close()
end

-- Bounded cache of decompressed terrain chunks (~7 MB each; 12 chunks <= ~88 MB)
local chunks = {}
local chunk_order = {}
local max_cached_chunks = 12

local function get_chunk(chunk_number)
	local chunk = chunks[chunk_number]
	if chunk then
		return chunk
	end

	local compressed = compressed_chunks[chunk_number]
	if not compressed then
		error("[" .. modname .. "] Missing terrain chunk: " .. tostring(chunk_number))
	end

	chunk = assert(
		core.decompress(compressed, "deflate"),
		"[" .. modname .. "] Failed to decompress terrain chunk: " .. tostring(chunk_number)
	)

	if #chunk_order >= max_cached_chunks then
		local oldest = table.remove(chunk_order, 1)
		chunks[oldest] = nil
	end
	chunks[chunk_number] = chunk
	chunk_order[#chunk_order + 1] = chunk_number
	return chunk
end

local function get_raw_data(column, row)
	if row < 0 then
		row = 0
	elseif row >= rows_total then
		row = rows_total - 1
	end
	column = column % columns_total
	local chunk_number = math.floor(row / rows_per_chunk)
	local offset = (row - chunk_number * rows_per_chunk) * row_size + column
	return get_chunk(chunk_number):byte(offset + 1)
end

local function get_interpolated_data(longitude, latitude)
	local row = (half_pi - latitude) * radians_to_pixels
	longitude = longitude % two_pi
	local column = longitude * radians_to_pixels
	local row0 = math.floor(row)
	local drow = row - row0
	local column0 = math.floor(column)
	local dcolumn = column - column0
	local v00 = get_raw_data(column0, row0)
	local v10 = get_raw_data(column0 + 1, row0)
	local v01 = get_raw_data(column0, row0 + 1)
	local v11 = get_raw_data(column0 + 1, row0 + 1)
	local v0 = v00 * (1 - dcolumn) + v10 * dcolumn
	local v1 = v01 * (1 - dcolumn) + v11 * dcolumn
	return v0 * (1 - drow) + v1 * drow
end

local function height_by_longitude_latitude(longitude, latitude)
	return get_interpolated_data(longitude, latitude) * nodes_per_height_unit
end

-- Register lunar stone nodes
local stone_sounds
if core.global_exists("default") and type(default.node_sound_stone_defaults) == "function" then
	stone_sounds = default.node_sound_stone_defaults()
end

local moonstone = {}
local block_prefix = modname .. ":moonstone_"

for i = 16, 244, 4 do
	local name = block_prefix .. i
	core.register_node(name, {
		description = "Moon stone " .. i,
		tiles = { "moon_moonstone" .. i .. ".png" },
		groups = { cracky = 3, stone = 1 },
		sounds = stone_sounds,
	})
end

local max_brightness = (244 - 16) / 4 -- 57

for i = 0, max_brightness do
	moonstone[i] = core.get_content_id(block_prefix .. (16 + i * 4))
end

-- Resolve fallback stone content ID cleanly even when Minetest Game (default) is not installed
local c_vacuum = core.CONTENT_AIR
local c_stone = moonstone[math.floor(max_brightness / 2)]

core.register_on_mods_loaded(function()
	if core.registered_nodes["default:stone"] then
		c_stone = core.get_content_id("default:stone")
	end
end)

-- Load NASA LROC albedo data at load time (only if albedo shading is enabled)
local albedo_width = 4096
local albedo_height = 2048
local albedo_radians_to_pixels = albedo_height / math.pi
local albedo_data = nil

if use_albedo then
	local albedo_filename = mypath .. "terrain" .. path_separator .. "albedo4096x2048.dat"
	local f = assert(io.open(albedo_filename, "rb"), "Failed to open albedo data: " .. albedo_filename)
	albedo_data = f:read("*a")
	f:close()
end

local function get_raw_albedo(column, row)
	if row < 0 then
		row = 0
	elseif row >= albedo_height then
		row = albedo_height - 1
	end
	column = column % albedo_width
	return albedo_data:byte(1 + row * albedo_width + column)
end

local function get_interpolated_block(longitude, latitude)
	local row = (half_pi - latitude) * albedo_radians_to_pixels
	longitude = longitude % two_pi
	local column = longitude * albedo_radians_to_pixels
	local row0 = math.floor(row)
	local drow = row - row0
	local column0 = math.floor(column)
	local dcolumn = column - column0
	local v00 = get_raw_albedo(column0, row0)
	local v10 = get_raw_albedo(column0 + 1, row0)
	local v01 = get_raw_albedo(column0, row0 + 1)
	local v11 = get_raw_albedo(column0 + 1, row0 + 1)
	local v0 = v00 * (1 - dcolumn) + v10 * dcolumn
	local v1 = v01 * (1 - dcolumn) + v11 * dcolumn
	local val = v0 * (1 - drow) + v1 * drow
	local idx = math.floor(val * (max_brightness + 1) / 255 + math.random())
	if idx < 0 then
		idx = 0
	elseif idx > max_brightness then
		idx = max_brightness
	end
	return moonstone[idx]
end

local function clamp_unit(v)
	if v < -1 then
		return -1
	elseif v > 1 then
		return 1
	end
	return v
end

local equaldistance

local orthographic = {
	get_longitude_latitude = function(x, _y0, z, farside, allow_oversize)
		x = x * land_normalize
		z = z * land_normalize
		local xz2 = x * x + z * z
		if xz2 > 1 then
			if allow_oversize then
				local r = math.sqrt(xz2)
				x = x / r
				z = z / r
				xz2 = 1
			else
				return nil
			end
		end
		local y = math.sqrt(math.max(0, 1 - xz2))
		local longitude
		if y < 1e-8 and math.abs(x) < 1e-8 then
			longitude = 0
		else
			longitude = atan2(x, y)
		end
		if farside then
			longitude = longitude + math.pi
			if longitude > math.pi then
				longitude = longitude - two_pi
			end
		end
		return longitude, math.asin(clamp_unit(z))
	end,

	get_xz_from_longitude_latitude = function(longitude, latitude)
		local z = math.sin(latitude) / land_normalize
		if longitude < -half_pi or longitude > half_pi then
			longitude = longitude - math.pi
		end
		local x = math.cos(latitude) * math.sin(longitude) / land_normalize
		return x, z
	end,

	goto_latitude_longitude_degrees = function(name, latitude, longitude, feature_name)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end

		local lat_deg = tonumber(latitude)
		local lon_deg = tonumber(longitude)
		if not lat_deg or not lon_deg then
			return false, "Invalid coordinates."
		end

		local side = 0
		if lon_deg < -90 or lon_deg > 90 then
			side = 1
		end
		local lat_rad = lat_deg * math.pi / 180
		local lon_rad = lon_deg * math.pi / 180
		if lat_rad < -half_pi or lat_rad > half_pi or lon_rad < -math.pi or lon_rad > math.pi then
			return false, "Out of range. Latitude must be in [-90, 90] and longitude in [-180, 180]."
		end

		local x, z = projection.get_xz_from_longitude_latitude(lon_rad, lat_rad)
		local y = math.floor(height_by_longitude_latitude(lon_rad, lat_rad) + offsets[side]) + 1.5
		player:set_pos(vector.new(x, y, z))

		if feature_name then
			core.log("action", "[" .. modname .. "] " .. name .. " jumping to " .. feature_name .. " at " .. x .. " " .. y .. " " .. z)
			return true, "Jumping to " .. feature_name .. "."
		else
			core.log("action", "[" .. modname .. "] " .. name .. " jumping to " .. x .. " " .. y .. " " .. z)
			return true, string.format("Jumping to latitude %.4f, longitude %.4f.", lat_deg, lon_deg)
		end
	end,

	generate = function(minp, maxp, data, area, vacuum, stone)
		local offset, farside
		if minp.y <= farside_below then
			-- Assumes a mapchunk never spans between farside and nearside
			offset = offsets[1]
			farside = true
		else
			offset = offsets[0]
			farside = false
		end

		local min_solid_y = offset - thickness
		local max_solid_y = offset + max_height_nodes

		-- Chunk is completely above or below the lunar slab (singlenode is already air)
		if minp.y > max_solid_y or maxp.y < min_solid_y then
			return false
		end

		local allow_oversize = teleport and projection == equaldistance
		local ystride = area.ystride
		local modified = false

		for z = minp.z, maxp.z do
			for x = minp.x, maxp.x do
				local longitude, latitude = projection.get_longitude_latitude(x, 0, z, farside, allow_oversize)
				if longitude then
					local f = math.floor(height_by_longitude_latitude(longitude, latitude) + offset)
					local y_start = math.max(minp.y, math.ceil(min_solid_y))
					local y_end = math.min(maxp.y, f)
					if y_start <= y_end then
						local block = use_albedo and get_interpolated_block(longitude, latitude) or stone
						local vi = area:index(x, y_start, z)
						for _ = y_start, y_end do
							data[vi] = block
							vi = vi + ystride
						end
						modified = true
					end
				end
			end
		end

		return modified
	end,
}

equaldistance = {
	get_longitude_latitude = function(x, _y0, z, farside, allow_oversize)
		x = x * land_normalize
		z = z * land_normalize
		local xz2 = x * x + z * z

		if xz2 > 2 or (xz2 > 1 and not allow_oversize) then
			return nil
		end

		local xz = math.sqrt(xz2)

		if xz < 1e-8 then
			if farside then
				return math.pi, 0
			else
				return 0, 0
			end
		end

		local adjustment = math.sin(xz * half_pi) / xz
		x = x * adjustment
		z = z * adjustment

		local y = math.sqrt(math.max(0, 1 - x * x - z * z))

		local longitude = atan2(x, y)
		if farside then
			longitude = longitude + math.pi
			if longitude > math.pi then
				longitude = longitude - two_pi
			end
		end

		if xz > 1 then
			if longitude >= 0 then
				longitude = math.pi - longitude
			else
				longitude = -math.pi - longitude
			end
		end

		return longitude, math.asin(clamp_unit(z))
	end,

	get_xz_from_longitude_latitude = function(longitude, latitude)
		local z = math.sin(latitude)
		if longitude < -half_pi or longitude > half_pi then
			longitude = longitude - math.pi
		end
		local x = math.cos(latitude) * math.sin(longitude)

		local xz = math.sqrt(x * x + z * z)

		if xz < 1e-8 then
			return x / land_normalize, z / land_normalize
		end

		local adjustment = math.asin(clamp_unit(xz)) / half_pi / xz

		return x * adjustment / land_normalize, z * adjustment / land_normalize
	end,

	goto_latitude_longitude_degrees = orthographic.goto_latitude_longitude_degrees,
	generate = orthographic.generate,
}

local sphere = {
	get_longitude_latitude = function(x, y, z, _farside)
		local r = math.sqrt(x * x + y * y + z * z)

		if r < 1e-8 then
			return 0, 0
		end

		local latitude = math.asin(clamp_unit(z / r))
		local longitude = atan2(x, y)

		return longitude, latitude
	end,

	get_block = function(x, y, z, vacuum, stone)
		local r = math.sqrt(x * x + y * y + z * z)

		if r < inner_radius_nodes - 5 then
			return stone
		elseif outer_radius_nodes < r then
			return vacuum
		end

		local nx = x / r
		local ny = y / r
		local nz = z / r

		local latitude = math.asin(clamp_unit(nz))
		local longitude = atan2(nx, ny)

		if r <= inner_radius_nodes + height_by_longitude_latitude(longitude, latitude) then
			if use_albedo then
				return get_interpolated_block(longitude, latitude)
			else
				return stone
			end
		else
			return vacuum
		end
	end,

	generate = function(minp, maxp, data, area, vacuum, stone)
		local block_radius = vector.distance(minp, maxp) / 2
		local r = vector.length(vector.multiply(vector.add(minp, maxp), 0.5))

		if r + block_radius < inner_radius_nodes then
			for pos in area:iterp(minp, maxp) do
				data[pos] = stone
			end
			return true
		elseif outer_radius_nodes < r - block_radius then
			-- Entire chunk is outside the lunar sphere (singlenode is already air)
			return false
		else
			for z = minp.z, maxp.z do
				for y = minp.y, maxp.y do
					local vi = area:index(minp.x, y, z)
					for x = minp.x, maxp.x do
						data[vi] = projection.get_block(x, y, z, vacuum, stone)
						vi = vi + 1
					end
				end
			end
			return true
		end
	end,

	goto_latitude_longitude_degrees = function(name, latitude, longitude, feature_name)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end

		local lat_deg = tonumber(latitude)
		local lon_deg = tonumber(longitude)
		if not lat_deg or not lon_deg then
			return false, "Invalid coordinates."
		end

		local lat_rad = lat_deg * math.pi / 180
		local lon_rad = lon_deg * math.pi / 180
		if lat_rad < -half_pi or lat_rad > half_pi or lon_rad < -math.pi or lon_rad > math.pi then
			return false, "Out of range. Latitude must be in [-90, 90] and longitude in [-180, 180]."
		end

		local nx = math.cos(lat_rad) * math.sin(lon_rad)
		local ny = math.cos(lat_rad) * math.cos(lon_rad)
		local nz = math.sin(lat_rad)
		local r = inner_radius_nodes + height_by_longitude_latitude(lon_rad, lat_rad) + 1.5
		local x = nx * r
		local y = ny * r
		local z = nz * r
		if ny < 0 then
			y = y - 2
		end

		player:set_pos(vector.new(x, y, z))

		if feature_name then
			core.log("action", "[" .. modname .. "] " .. name .. " jumping to " .. feature_name .. " at " .. x .. " " .. y .. " " .. z)
			return true, "Jumping to " .. feature_name .. "."
		else
			core.log("action", "[" .. modname .. "] " .. name .. " jumping to " .. x .. " " .. y .. " " .. z)
			return true, string.format("Jumping to latitude %.4f, longitude %.4f.", lat_deg, lon_deg)
		end
	end,
}

core.log("action", "[" .. modname .. "] Moon projection mode: " .. projection_mode)

if projection_mode == "sphere" then
	projection = sphere
else
	if projection_mode == "equaldistance" then
		projection = equaldistance
	else
		projection = orthographic
	end

	offsets[0] = -height_by_longitude_latitude(0, 0)
	farside_below = math.min(-5000, math.floor(offsets[0] - thickness - 500))
	offsets[1] = farside_below - max_height_nodes
	farside_threshold = (offsets[0] - thickness + farside_below) / 2
end

local vm_data = {}

core.register_on_generated(function(minp, maxp, _seed)
	local vm, emin, emax = core.get_mapgen_object("voxelmanip")
	if not vm then
		return
	end
	local data = vm:get_data(vm_data)
	local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })

	local modified = projection.generate(minp, maxp, data, area, c_vacuum, c_stone)
	if modified then
		vm:set_data(data)
		vm:calc_lighting()
		vm:write_to_map()
	end
end)

-- Preload lunar feature catalog at load time (sandbox-safe; instant /goto lookups)
local features_by_key = {}
local features_list = {}
do
	local features_path = mypath .. "features.txt"
	local f = assert(io.open(features_path, "r"), "Failed to open feature list: " .. features_path)
	for line in f:lines() do
		local key, fullname, lat, lon = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|")
		if key then
			local lat_n = tonumber(lat)
			local lon_n = tonumber(lon)
			if lat_n and lon_n then
				local entry = {
					key = key,
					name = fullname,
					lat = lat_n,
					lon = lon_n,
				}
				if not features_by_key[key] then
					features_by_key[key] = entry
				end
				features_list[#features_list + 1] = entry
			end
		end
	end
	f:close()
end

local function find_feature(name)
	local lower_name = name:lower():gsub("[^a-z0-9]", "")
	local name_length = #lower_name
	if name_length == 0 then
		return nil
	end

	local exact = features_by_key[lower_name]
	if exact then
		return exact.lat, exact.lon, exact.name
	end

	for i = 1, #features_list do
		local entry = features_list[i]
		if entry.key:sub(1, name_length) == lower_name then
			return entry.lat, entry.lon, entry.name
		end
	end

	return nil
end

core.register_chatcommand("goto", {
	params = "<latitude> <longitude> | <feature name>",
	description = "Go to location on the Moon. Negative latitudes are south and negative longitudes are west.",
	func = function(name, args)
		if not args or args:match("^%s*$") then
			return false, "Usage: /goto <latitude> <longitude> or /goto <feature name>"
		end

		local latitude, longitude = args:match("^%s*([+-]?%d*%.?%d+)[%s,]+([+-]?%d*%.?%d+)%s*$")
		local feature_name = nil
		if not longitude or not tonumber(latitude) or not tonumber(longitude) then
			latitude, longitude, feature_name = find_feature(args)
			if not latitude then
				return false, "Cannot find lunar feature: " .. args
			end
		end
		return projection.goto_latitude_longitude_degrees(name, latitude, longitude, feature_name)
	end,
})

core.register_chatcommand("where", {
	params = "",
	description = "Get latitude and longitude of current position on the Moon.",
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		local pos = player:get_pos()
		local farside = pos.y < farside_threshold -- ignored in sphere mode
		local longitude, latitude = projection.get_longitude_latitude(pos.x, pos.y, pos.z, farside)
		if longitude then
			return true, string.format(
				"Latitude: %.4f, longitude: %.4f",
				latitude * 180 / math.pi,
				longitude * 180 / math.pi
			)
		else
			return false, "Out of range."
		end
	end,
})

core.register_on_joinplayer(function(player)
	player:set_physics_override({ gravity = gravity })

	if sky == "black" then
		player:set_sky({
			base_color = "#000000",
			type = "plain",
			clouds = false,
		})
		player:set_sun({ visible = false, sunrise_visible = false })
		player:set_moon({ visible = false })
		player:set_stars({ visible = false })
	elseif sky == "fancy" then
		-- Texture order: Y+, Y-, X-, X+, Z+, Z-
		player:set_sky({
			base_color = "#000000",
			type = "skybox",
			textures = {
				"sky_pos_y.png",
				"sky_neg_y.png",
				"sky_neg_z.png",
				"sky_pos_z.png",
				"sky_neg_x.png",
				"sky_pos_x.png",
			},
			clouds = false,
		})
		player:set_sun({ visible = false, sunrise_visible = false })
		player:set_moon({ visible = false })
		player:set_stars({ visible = false })
	end

	local name = player:get_player_name()
	local privs = core.get_player_privs(name)
	if not privs.fly then
		privs.fly = true
		core.set_player_privs(name, privs)
	end
end)

-- Spawn players cleanly on the lunar surface
local function get_default_spawn_pos()
	if projection == sphere then
		return vector.new(0, math.floor(inner_radius_nodes + height_by_longitude_latitude(0, 0)) + 2, 0)
	else
		return vector.new(0, math.floor(height_by_longitude_latitude(0, 0) + offsets[0]) + 2, 0)
	end
end

core.register_on_newplayer(function(player)
	player:set_pos(get_default_spawn_pos())
end)

core.register_on_respawnplayer(function(player)
	player:set_pos(get_default_spawn_pos())
	return true
end)

if teleport and projection ~= sphere then
	local teleport_radius = projection == equaldistance and (radius_nodes + 2) or (radius_nodes + 0.5)
	core.register_globalstep(function()
		local players = core.get_connected_players()
		for i = 1, #players do
			local player = players[i]
			local pos = player:get_pos()
			local r = hypot(pos.x, pos.z)
			if r > teleport_radius then
				local farside = pos.y < farside_threshold
				local longitude, latitude = projection.get_longitude_latitude(
					pos.x, pos.y, pos.z, farside, true
				)
				if longitude then
					local lat_deg = latitude * 180 / math.pi
					local lon_deg = longitude * 180 / math.pi
					if projection == orthographic then
						-- Orthographic clamps to the disc edge; step slightly inside the opposite side
						if lat_deg > 89.5 then
							lat_deg = 89.5
						elseif lat_deg < -89.5 then
							lat_deg = -89.5
						end
						if lon_deg >= 0 then
							lon_deg = farside and 89.5 or 90.5
						else
							lon_deg = farside and -89.5 or -90.5
						end
					end
					local name = player:get_player_name()
					core.chat_send_player(
						name,
						string.format("Teleporting to other side, latitude: %.4f, longitude: %.4f", lat_deg, lon_deg)
					)
					projection.goto_latitude_longitude_degrees(name, lat_deg, lon_deg)
				end
			end
		end
	end)
end
