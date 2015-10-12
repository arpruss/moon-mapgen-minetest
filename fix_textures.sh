# fix textures exported as skybox from SpaceEngine
# Actually, the textures I use are an amalgam. The top square is generated with planets active
# so as to show the earth while the other squares are generated with planets inactive not to
# show moon terrain.
gamma=1.3
convert sky_neg_x.tga -gamma $gamma textures/sky_neg_x.png
convert sky_neg_y.tga -gamma $gamma -rotate 180 textures/sky_neg_y.png
convert sky_neg_z.tga -gamma $gamma textures/sky_neg_z.png
convert sky_pos_x.tga -gamma $gamma textures/sky_pos_x.png
convert sky_pos_y.tga -gamma $gamma -rotate 180 textures/sky_pos_y.png
convert sky_pos_z.tga -gamma $gamma textures/sky_pos_z.png
