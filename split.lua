local f = assert(io.open("moon_terrain.dat", "rb"))

chunkSize = 360 * 64 * 10
local data = f:read("*all")
print (#data)
f:close()

for i=0,180/5-1 do
        print(i)
	f = assert(io.open("terrain/"..i..".dat", "wb"))
	local start = 1 + i*5*64*360*64
	f:write(data:sub(start, start+5*64*360*64-1))
	f:close()
end

