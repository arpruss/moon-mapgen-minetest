from os import system
from random import randint,choice
from struct import pack

def clamp(n): return max(0, min(n, 255))

for value in range(16,245,4):
	p = open("tmp.bin", "wb")
	for y in range(16):
		x = 0
		while x < 16:
			v = choice((value,clamp(value-8),clamp(value-4),clamp(value),clamp(value+4),clamp(value+8)))
			n = randint(1,6)
			while x < 16 and n > 0:
				p.write(pack("B", v))
				x += 1
				n -= 1
	p.close()
	system("convert -depth 8 -size 16x16 gray:tmp.bin textures/moon_moonstone"+str(value)+".png")
	

