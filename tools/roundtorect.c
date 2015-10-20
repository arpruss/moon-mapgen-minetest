#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include <assert.h>

#define WIDTH 4096
#define HEIGHT 2048

#define NEARSIDE_DIM 5000
#define FARSIDE_DIM 782

#define MID_WIDTH 4096
#define MID_HEIGHT 1366

double get_raw_data(unsigned char* in, int side, int column, int row)
{
	if (column < 0) column = 0;
	if (column >= side) column = side-1;
	if (row < 0) row = 0;
	if (row >= side) row = side-1;
	return in[column+row*side];
}

int getValue(unsigned char* in, int side, double longitude, double latitude, double scale)
{
	double x = side/2+scale*(side/2)*cos(latitude)*sin(longitude);
	double y = side/2-scale*(side/2)*sin(latitude);
	int row0 = (int)floor(y);
    double drow = y - row0;
    int column0 = (int)floor(x);
    double dcolumn = x - column0;
    double v00 = get_raw_data(in,side,column0,row0);
    double v10 = get_raw_data(in,side,column0+1,row0);
    double v01 = get_raw_data(in,side,column0,row0+1);
    double v11 = get_raw_data(in,side,column0+1,row0+1);
    double v0 = v00 * (1-dcolumn) + v10 * dcolumn;
    double v1 = v01 * (1-dcolumn) + v11 * dcolumn;
    return v0 * (1-drow) + v1 * drow;
}

main() 
{
	puts("Reading nearside");
    unsigned char* nearside = malloc(NEARSIDE_DIM*NEARSIDE_DIM);
	assert(nearside != NULL);
	FILE *f = fopen("nearside.raw", "rb");
	assert(f != NULL);
	if (NEARSIDE_DIM*NEARSIDE_DIM != fread(nearside,1,NEARSIDE_DIM*NEARSIDE_DIM,f)) {
		fputs("Err 1", stderr);
	}
	fclose(f);
	puts("Reading farside");
	unsigned char* farside = malloc(FARSIDE_DIM*FARSIDE_DIM);
	assert(farside != NULL);
	f = fopen("farside.raw", "rb");
	assert(f != NULL);
	if (FARSIDE_DIM*FARSIDE_DIM != fread(farside,1,FARSIDE_DIM*FARSIDE_DIM,f)) {
		fputs("Err 2", stderr);
	}
	fclose(f); 
	puts("Reading mid");
	unsigned char* mid = malloc(MID_HEIGHT*MID_WIDTH);
	assert(farside != NULL);
	f = fopen("wac643.raw", "rb");
	assert(f != NULL);
	if (MID_HEIGHT*MID_WIDTH != fread(mid,1,MID_HEIGHT*MID_WIDTH,f)) {
		fputs("Err 3", stderr);
	}
	fclose(f); 
	unsigned char* out = malloc(WIDTH*HEIGHT);
	assert(out != NULL);
	
	f = fopen("albedo.raw", "wb");
	
	int x,y;
	
	for (y=0; y<HEIGHT ; y++) for (x=0; x< WIDTH; x++)  {
		double longitude = 2 * M_PI * x / WIDTH;
		double latitude = M_PI * (HEIGHT / 2 - y ) / HEIGHT;
		int value;
		if (HEIGHT / 6 <= y && y < HEIGHT / 6 + MID_HEIGHT)
			value = mid[(y-HEIGHT/6)*MID_WIDTH+x];
		else if (x  < WIDTH/4) 
			value = getValue(nearside,NEARSIDE_DIM,longitude,latitude,779./782.);
		else if (x >= WIDTH/4*3)
			value = getValue(nearside,NEARSIDE_DIM,longitude,latitude,779./782.);
		else {
			value = getValue(farside,FARSIDE_DIM,longitude-M_PI,latitude,779/782.);
			value = 255 - (255 - value)*(255-184)/(255-170);
		}
		fputc(value, f);
	}

	fclose(f);
	
	free(nearside);
	free(farside);
	free(out);
}
