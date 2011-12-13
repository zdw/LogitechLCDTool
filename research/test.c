#include <strings.h>
#include <stdio.h>;

  enum
  {
    G15_LCD_OFFSET = 32,
    G15_LCD_HEIGHT = 43,
    G15_LCD_WIDTH = 160
  };

  enum
  {
    G15_BUFFER_LEN = 0x03e0
  };

static void dumpPixmapIntoLCDFormat(unsigned char *lcd_buffer, unsigned char const *data);

int main() {

	unsigned char in[G15_BUFFER_LEN];
	bzero(in, G15_BUFFER_LEN);
	int i;
	
	for (i = 0; i < 21; i++) {
		in[i] = 0xff;
	}
	
	
	unsigned char out[G15_BUFFER_LEN];
	bzero(out, G15_BUFFER_LEN);
	dumpPixmapIntoLCDFormat(out, in);
    out[0] = 0x03;

	for (i = 0; i < G15_BUFFER_LEN; i++) {
		printf("%02X ", in[i]);
		if (! ((i + 1) % 20)) printf("\n");
	}
	printf("\n--------\n");
	for (i = 0; i < G15_BUFFER_LEN; i++) {
		printf("%02X ", out[i]);
		if (! ((i + 1) % 20)) printf("\n");
	}

	printf("\n--------\n");




}








static void dumpPixmapIntoLCDFormat(unsigned char *lcd_buffer, unsigned char const *data)
{
  unsigned int offset_from_start = G15_LCD_OFFSET;
  unsigned int curr_row = 0;
  unsigned int curr_col = 0;
  
  for (curr_row=0;curr_row<G15_LCD_HEIGHT;++curr_row)
  {
    for (curr_col=0;curr_col<G15_LCD_WIDTH;++curr_col)
    {
      unsigned int pixel_offset = curr_row*G15_LCD_WIDTH + curr_col;
      unsigned int byte_offset = pixel_offset / 8;
      unsigned int bit_offset = pixel_offset % 8;
      unsigned int val = data[byte_offset] & 1<<(7-bit_offset);
      
      unsigned int row = curr_row / 8;
      unsigned int offset = G15_LCD_WIDTH*row + curr_col;
      unsigned int bit = curr_row % 8;
    
/*
      if (val)
        printf("Setting pixel at row %d col %d to %d offset %d bit %d\n",curr_row,curr_col, val, offset, bit);
      */
      if (val)
        lcd_buffer[offset_from_start + offset] = lcd_buffer[offset_from_start + offset] | 1 << bit;
      else
        lcd_buffer[offset_from_start + offset] = lcd_buffer[offset_from_start + offset]  &  ~(1 << bit);
    }
  }
}
