/******
*
FFMpeg Tutorial
http://www.dranger.com/ffmpeg/tutorial01.html
*
To compile:
gcc -o cgo cgo.c -lsqlite3 -lavutil -lavformat -lavcodec -lswscale -lz -lavutil -lm -Wall
*
To run:
./cgo <video.mp4>
******/
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <math.h>
#include <time.h>
#include <string.h>
/** DB stuff **/
#include<stdio.h>
#include<sqlite3.h>
#include<stdlib.h>

int AvgFrame(AVFrame *pFrameFoo, int width, int height, int iFrame, char *argv[], sqlite3 *handle, double fps);
int AvgFrameText(AVFrame *pFrameFoo, int width, int height, int iFrame, int key);
int cgo(AVFrame *pFrameFoo, int width, int height, int iFrame, char *argv[], sqlite3 *handle);

double prevY, prevU, prevV = 0.0;
int split = -1;
int split_second = 0;

int main(int argc, char *argv[]) {

  /*** DB initialization ***/
  int retval = 0;

  // Create a handle for database connection, create a pointer to sqlite3
  sqlite3 *handle;

  // try to create the database. If it doesnt exist, it would be created
  // pass a pointer to the pointer to sqlite3, in short sqlite3**

  retval = sqlite3_open("/home/gsc/test_suj_utube_temp.db",&handle);
  // If connection failed, handle returns NULL
  if(retval){
	printf("Database connection failed\n");
	return -1;
  }

  if ( mode != 2 ) {
	  char query1[] = "create table allmovies (allmovieskey INTEGER PRIMARY KEY,name TEXT,fps INTEGER);";
	  // Execute the query for creating the table
	  retval = sqlite3_exec(handle,query1,0,0,0);
	  char query2[] = "PRAGMA count_changes = OFF";
	  retval = sqlite3_exec(handle,query2,0,0,0);
	  char query3[] = "PRAGMA synchronous = OFF";
	  retval = sqlite3_exec(handle,query3,0,0,0);
	  
	  char table_query[150];
	  memset(table_query, 0, 150);
	  if (mode == 1) {
		sprintf(table_query,"create table '%s' (frame INTEGER, b1 FLOAT, b2 FLOAT, b3 FLOAT, b4 FLOAT, b5 FLOAT, b6 FLOAT, b7 FLOAT, b8 FLOAT);",argv[2]);
	  } else if (mode == 0) {
		sprintf(table_query,"create table '%s' (s_end INTEGER, luma INTEGER, chromau INTEGER, chromav INTEGER);",argv[2]);
	  }
	  retval = sqlite3_exec(handle,table_query,0,0,0);
	  if (retval) {
		char error [100];
		memset(error, 0, 100);
		sprintf(error,"Table for movie %s already exists!\n",argv[2]);
		printf("%s",error);
		sqlite3_close(handle);
		return -1;
	  }
	  /*** DB init finished ***/
  }

  printf("Analyzing video %s\n",argv[2]);

  av_register_all();
  
  AVFormatContext *pFormatCtx;

  // Open video file
  if(av_open_input_file(&pFormatCtx, argv[2], NULL, 0, NULL)!=0)
    return -1; // Couldn't open file
  
  // Retrieve stream information
  if(av_find_stream_info(pFormatCtx)<0)
    return -1; // Couldn't find stream information

  // Dump information about file onto standard error
  dump_format(pFormatCtx, 0, argv[2], 0);

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
	sqlite3_close(handle);
    return -1; // Codec not found
  }
  // Open codec
  if(avcodec_open(pCodecCtx, pCodec)<0) {
    sqlite3_close(handle);
    return -1; // Could not open codec
  }

  AVFrame *pFrame;
  AVFrame *pFrameYUV;

  // Allocate video frame
  pFrame=avcodec_alloc_frame();
  
  // Allocate an AVFrame structure
  pFrameYUV=avcodec_alloc_frame();
  if(pFrameYUV==NULL) {
    sqlite3_close(handle);
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
  struct SwsContext * sws_context;
  double fps = 0.0;

  if ( mode != 2) {
	  char allmovies_query[150];
	  memset(allmovies_query, 0, 150);
	  fps = (double)pFormatCtx->streams[videoStream]->r_frame_rate.num/(double)pFormatCtx->streams[videoStream]->r_frame_rate.den;
	  sprintf(allmovies_query, "insert into allmovies (name,fps) values ('%s',%f);", argv[2], fps);
	  retval = sqlite3_exec(handle,allmovies_query,0,0,0);
  }
  
  i=0;
  while(av_read_frame(pFormatCtx, &packet)>=0) {
  // Is this a packet from the video stream?
    if(packet.stream_index==videoStream) {
    // Decode video frame
      avcodec_decode_video(pCodecCtx, pFrame, &frameFinished, packet.data, packet.size);
      
      // Did we get a video frame?
      if(frameFinished) {
        // Convert the image from its native format to YUV (PIX_FMT_YUV420P)
        //img_convert((AVPicture *)pFrameYUV, PIX_FMT_YUV420P, (AVPicture*)pFrame, pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height);
        sws_context = sws_getContext(pCodecCtx->width, pCodecCtx->height, pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height, PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);
        sws_scale(sws_context, pFrame->data, pFrame->linesize, 0, pCodecCtx->height, pFrameYUV->data, pFrameYUV->linesize);
        sws_freeContext(sws_context);
		
		if (mode == 0)
			retval = AvgFrame(pFrameYUV, pCodecCtx->width, pCodecCtx->height, i++, argv, handle, fps);
		else if (mode == 1)
			retval = cgo(pFrameYUV, pCodecCtx->width, pCodecCtx->height, i++, argv, handle);
		else  if (mode == 2)
			retval = AvgFrameText(pFrameYUV, pCodecCtx->width, pCodecCtx->height, i++, pFrame->key_frame);
		else {
			printf("Please choose a mode! (-cgo or not)\n");
		}
      }
    }
  }
  
  //printf("%s\n",allmovies_query);
  //printf("fps %2.2f\n", (double)pFormatCtx->streams[videoStream]->r_frame_rate.num/(double)pFormatCtx->streams[videoStream]->r_frame_rate.den);
  
  // Free the packet that was allocated by av_read_frame
  av_free_packet(&packet);
  
  // Free the YUV image
  av_free(buffer);
  av_free(pFrameYUV);

  // Free the YUV frame
  av_free(pFrame);

  // Close the codec
  avcodec_close(pCodecCtx);

  // Close the video file
  av_close_input_file(pFormatCtx);
  
  // Close DB handler
  sqlite3_close(handle);

  return 0;
  
}

int cgo(AVFrame *pFrameFoo, int width, int height, int iFrame, char *argv[], sqlite3* handle) {
  int y = 1;
  int x = 1;
  
  int N = 2;
  int M = 4;
  
  //Implement malloc
  unsigned int Gx[width-2];
  memset(Gx, 0, width-2);
  unsigned int Gy[height-2];
  memset(Gy, 0, height-2);
  float a = 0.0;
  float b = 0.0;
  
  int j = 0;
  int k = 0;
  float cgo[N][M];
  memset(cgo, 0, N*M);
  
  int retval = 0;
	
  for(y = 1; y < (height-1); y++) {
	for (x = 1; x < (width-1); x++) {
		Gx[x] = pFrameFoo->data[0][y*pFrameFoo->linesize[0] + x + 1] - pFrameFoo->data[0][y*pFrameFoo->linesize[0] + x - 1];
	}
  }
	 
  for(y = 1; y < (height-1); y++){
	for (x = 1; x < (width-1); x++) {
		Gy[y] = pFrameFoo->data[0][(y - 1)*pFrameFoo->linesize[0] + x ] - pFrameFoo->data[0][(y + 1)*pFrameFoo->linesize[0] + x];
	}
  }
		
  //magnitude
  //r = sqrt(Gx[x]**2 + Gy[y]**2)
  //orientation
  //o = arctan(Gy[y]/Gx[x])
  
  
  for (j = 0; j < N ; j++) {
	for (k = 0; k < M ; k++) {
		//printf("[%d][%d]\n",j,k);
		a = 0.0;
		b = 0.0;
		
		for (x = (j*(width/N))+1; x < ((j+1)*(width/N))+1; x++) {
			for(y = (k*(height/M))+1; y < ((k+1)*(height/M))+1; y++) {
				//printf("%d\n",Gx[x]);
				//printf("[%d %d] = %d %d\n",x,y,Gx[x],Gy[y]);
				if (Gx[x] != 0)
					a+=atan(Gy[y]/Gx[x])*sqrt(Gx[x]*Gx[x] + Gy[y]*Gy[y]);
		
				b+=sqrt(Gx[x]*Gx[x] + Gy[y]*Gy[y]);
			}
		}
		//printf("row\n");
		//printf("%f %f\n",a,b);
		if (b != 0)
			cgo[j][k] = a/b;
		
	}
	//printf("column\n");
  }
  
  //printf("%d;time;", iFrame);
  char blocks[200];
  memset(blocks, 0, 200);
  
  for (j = 0; j < N ; j++)
	for (k = 0; k < M ; k++)
		sprintf(blocks,"%s,%f",blocks,cgo[j][k]);
		
  //printf("\n");
  //printf("%s\n",blocks);
  
  char insert_query[500];
  memset(insert_query, 0, 500);
  sprintf(insert_query, "insert into '%s' values (%d%s)",argv[2],iFrame,blocks);

  //"insert into '%s' (frame,b1,b2,b3,b4,b5,b6,b7,b8) values (%d%s);"
  
  //printf("%s\n",insert_query);
  
  //printf("%d;time;%f\n", iFrame, c);
  retval = sqlite3_exec(handle,insert_query,0,0,0);
  
  if (retval)
	printf("%s\n",sqlite3_errmsg(handle));
  
  return retval;
}

int AvgFrame(AVFrame *pFrameFoo, int width, int height, int iFrame, char *argv[], sqlite3* handle, double fps) {
  int y = 0;
  int x = 0;
  
  int retval = 0;
  
  unsigned int luma = 0;
  unsigned int chromaV = 0;
  unsigned int chromaU = 0;
  float avgChromaU = 0.0;
  float avgLuma = 0.0;
  float avgChromaV = 0.0;
  
  char table_query[150];
  
  int max_hours = 3;
  int max_frames = max_hours*60*60*fps;
  
  for(y=0; y<height; y++){
    //printf("Luma %d\n",y);
    for (x=0; x<width; x++) {
      luma += pFrameFoo->data[0][y*pFrameFoo->linesize[0] + x];
    }
  }
  
  for(y=0; y<height/2; y++){
    //printf("Chroma %d\n",y);
    fflush(stdout);
    for (x=0; x<width/2; x++) {
      chromaU += pFrameFoo->data[2][y*pFrameFoo->linesize[2] + x];
      chromaV += pFrameFoo->data[1][y*pFrameFoo->linesize[1] + x];
    }
  }

  avgLuma = luma*1.0 / (height*width);
  avgChromaU = chromaU*1.0 / (height*width);
  avgChromaV = chromaV*1.0 / (height*width);
  
  //Splitting large files into several files if larger than max_frames = max_hours*60*60*fps
  if ( (iFrame%max_frames) == 0 ) {
    printf("split++ (%d->%d) at frame %d (%d)\n",split,split+1,iFrame,split_second);
	split_second = iFrame;
	split++;
	if (split != 0) {
		sprintf(table_query,"create table '%s_%d' (s_end INTEGER, luma INTEGER, chromau INTEGER, chromav INTEGER);",argv[2],split);
		sqlite3_exec(handle,table_query,0,0,0);
		sprintf(table_query,"insert into allmovies (name,fps) values ('%s_%d',%f);",argv[2],split,fps);
		sqlite3_exec(handle,table_query,0,0,0);
	}
  }
  
  char insert_query[500];
  memset(insert_query, 0, 500);
  //printf("%d;time;%f;%f;%f;%f\n", iFrame, avgLuma, fabs(avgLuma-prevY), avgChromaU, avgChromaV);
  if (split == 0) {
	sprintf(insert_query, "insert into '%s' values (%d,%f,%f,%f)",argv[2],iFrame,avgLuma,avgChromaU,avgChromaV);
  }
  else {
    sprintf(insert_query, "insert into '%s_%d' values (%d,%f,%f,%f)",argv[2],split,iFrame-split_second,avgLuma,avgChromaU,avgChromaV);
  }

  retval = sqlite3_exec(handle,insert_query,0,0,0);
  
  if (retval)
	printf("%s\n",sqlite3_errmsg(handle));
  
  prevY = avgLuma;
  prevU = avgChromaU;
  prevV = avgChromaV;
  
  return retval;
}

int AvgFrameText(AVFrame *pFrameFoo, int width, int height, int iFrame, int key) {
  int y = 0;
  int x = 0;
  
  int retval = 0;
  
  unsigned int luma = 0;
  unsigned int chromaV = 0;
  unsigned int chromaU = 0;
  float avgChromaU = 0.0;
  float avgLuma = 0.0;
  float avgChromaV = 0.0;
  
  //scene splitting
  int partH = height/3;
  int partW = width/4;
  //
  partH = 0;
  partW = 0;

  for(y=partH; y<height-partH; y++){
    //printf("Luma %d\n",y);
    for (x=partW; x<width-partW; x++) {
      luma += pFrameFoo->data[0][y*pFrameFoo->linesize[0] + x];
    }
  }

  for(y=0; y<height/2; y++){
    //printf("Chroma %d\n",y);
    fflush(stdout);
    for (x=0; x<width/2; x++) {
      chromaU += pFrameFoo->data[2][y*pFrameFoo->linesize[2] + x];
      chromaV += pFrameFoo->data[1][y*pFrameFoo->linesize[1] + x];
    }
  }

  avgLuma = luma*1.0 / (height*width);
  avgChromaU = chromaU*1.0 / (height*width);
  avgChromaV = chromaV*1.0 / (height*width);
  
  printf("%d;time;%f;%f;%f;%f\n", iFrame, avgLuma, fabs(avgLuma-prevY), avgChromaU, avgChromaV);
  //printf("%d;time;%f;%f;%d\n", iFrame, avgLuma, fabs(avgLuma-prevY),key);
  
  prevY = avgLuma;
  prevU = avgChromaU;
  prevV = avgChromaV;
  
  return retval;
}
