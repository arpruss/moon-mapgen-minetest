#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include <assert.h>

#define WIDTH 2048
#define HEIGHT 1024

#define NEARSIDE_DIM 5000
#define FARSIDE_DIM 5000

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
	unsigned char* out = malloc(WIDTH*HEIGHT);
	assert(out != NULL);
	
	f = fopen("albedo.raw", "wb");
	
	int x,y;
	
	for (x=0; x< WIDTH; x++) for (y=0; y<HEIGHT ; y++) {
		double longitude = 2 * M_PI * x / WIDTH;
		double latitude = 2 * M_PI * y / HEIGHT;
		int value;
		if (x  < WIDTH/4 || 3*WIDTH/4 <= x) 
			value = getValue(farside,FARSIDE_DIM,longitude,latitude);
		else 
			value = getValue(nearrside,NEARSIDE_DIM,longitude-M_PI,latitude);
		fputc(value, f);
	}

	fclose(f);
	
	free(nearside);
	free(farside);
	free(out);
}
