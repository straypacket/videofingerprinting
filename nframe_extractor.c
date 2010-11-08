/******
*
Based on FFMpeg Tutorial
http://www.dranger.com/ffmpeg/tutorial01.html
*
To compile:
Linux
gcc -o nfe nframe_extractor.c -static -lavutil -lavformat -lavcodec -lz -lm -Wall
OSX
gcc -o nfe nframe_extractor.c -I/opt/local/include -L/opt/local/lib -lavutil -lavformat -lavcodec -lz -lm -Wall
Static
gcc -o nfe nframe_extractor.c -static -lavformat -lavcodec -lswscale -lavutil -lpthread -lbz2 -lfaac -lfaad -lmp3lame -lvorbisenc -lvorbis -logg -lx264 -lxvidcore -lz -lm -lc -Wall -m32
*
To run:
./nfe video
******/
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <sys/time.h>
#include <string.h>

int main(int argc, char *argv[]) {
  
  char *inputsource = argv[1];

  av_register_all();
  AVFormatContext *pFormatCtx;

  // Open video file
  if(av_open_input_file(&pFormatCtx, inputsource, NULL, 0, NULL)!=0) {
	printf("Could't open file %s\n", argv[1]);
    return -1; // Couldn't open file
  }
  
  // Retrieve stream information
  if(av_find_stream_info(pFormatCtx)<0) {
    printf("Could't find stream information\n");
    return -1; // Couldn't find stream information
  }

  // Dump information about file onto standard error
  //dump_format(pFormatCtx, 0, inputsource, 0);

  int i;
  AVCodecContext *pCodecCtx;

  // Find the first video stream
  int videoStream=-1;
  for(i=0; i<pFormatCtx->nb_streams; i++)
    if(pFormatCtx->streams[i]->codec->codec_type==CODEC_TYPE_VIDEO) {
      videoStream=i;
      break;
    }
    
  if(videoStream==-1)
    return -1; // Didn't find a video stream
  
  // Get a pointer to the codec context for the video stream
  pCodecCtx=pFormatCtx->streams[videoStream]->codec;

  AVCodec *pCodec;

  // Find the decoder for the video stream
  pCodec=avcodec_find_decoder(pCodecCtx->codec_id);
  if(pCodec==NULL) {
    fprintf(stderr, "Unsupported codec!\n");
    return -1; // Codec not found
  }
  // Open codec
  if(avcodec_open(pCodecCtx, pCodec)<0)
    return -1; // Could not open codec

  AVFrame *pFrame;
  AVFrame *pFrameYUV;

  // Allocate video frame
  pFrame=avcodec_alloc_frame();
  
  // Allocate an AVFrame structure
  pFrameYUV=avcodec_alloc_frame();
  if(pFrameYUV==NULL) {
    return -1;
  }
  
  uint8_t *buffer;
  int numBytes;
  // Determine required buffer size and allocate buffer
  numBytes=avpicture_get_size(PIX_FMT_YUV420P, pCodecCtx->width, pCodecCtx->height);
  buffer=(uint8_t *)av_malloc(numBytes*sizeof(uint8_t));
  
  // Assign appropriate parts of buffer to image planes in pFrameYUV
  // Note that pFrameYUV is an AVFrame, but AVFrame is a superset
  // of AVPicture
  avpicture_fill((AVPicture *)pFrameYUV, buffer, PIX_FMT_YUV420P, pCodecCtx->width, pCodecCtx->height);
  
  int frameFinished = 0;
  AVPacket packet;
  av_init_packet(&packet);

  int nFrames = 0;
  while(av_read_frame(pFormatCtx, &packet)>=0) {
  // Is this a packet from the video stream?
    if(packet.stream_index==videoStream) {
    // Decode video frame
	  avcodec_decode_video2(pCodecCtx, pFrame, &frameFinished, &packet);
      // Did we get a video frame?
      if(frameFinished) {
		nFrames++;

      }
    }
  }
  printf("%d\n", nFrames);
  nFrames = 0;
  
  return 0;
}  