#include <wand/magick_wand.h>

void test_wand(void)
{
#define ThrowWandException(wand) \
  { \
    char *description; \
    ExceptionType severity; \
    description=MagickGetException(wand,&severity); \
    (void) fprintf(stderr,"%s %s %lu %s\n",GetMagickModule(),description); \
    description=(char *) MagickRelinquishMemory(description); \
    exit(-1); \
  } \

  MagickWand *mw = NULL;

  MagickWandGenesis();

  /* Create a wand */
  mw = NewMagickWand();

  /* Read the input image */
 MagickBooleanType retVal = MagickReadImage(mw,"../..//images/black_and_white/black1.jpg");
   if (retVal == MagickFalse) 
     ThrowWandException(mw); 
 
  PixelWand** pixels;
  PixelIterator* pixelIt = NewPixelIterator(mw);
  size_t width = MagickGetImageWidth(mw);
  size_t height = MagickGetImageHeight(mw);
  long y;
  double outputPattern[width][height];

  for (y=0; y < (long) height; y++) 
  { 
    pixels=PixelGetNextIteratorRow(pixelIt,&width);
    for (long x=0; x < (long) width; x++) { 
      outputPattern[x][y] = PixelGetBlack(pixels[x]); 
    }
  }

  for (y=0; y < (long) height; y++){ 
    for (long x=0; x < (long) width; x++) 
      printf("%f ", outputPattern[x][y]); 

    printf("\n\n\n");
  }

 /* write it */
  //MagickWriteImage(mw,"./black_out1.jpg");

  /* Tidy up */
  if(mw) mw = DestroyMagickWand(mw);

  MagickWandTerminus();
}

int main(){
  
  test_wand();
  return 0;
}
