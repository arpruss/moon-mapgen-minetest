from os import system
from random import randint
from struct import pack

for value in range(256):
	p = open("tmp.bin", "wb")
	for x in range(256):
		v = value + randint(-8,9)
		if v < 0: v = 0
		if v > 255: v = 255
		p.write(pack("B", v))
	p.close()
	system("convert -depth 8 -size 16x16 gray:tmp.bin textures/block"+str(value)+".png")
	