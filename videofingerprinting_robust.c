/******
*
FFMpeg Tutorial
http://www.dranger.com/ffmpeg/tutorial01.html
*
To compile:
Linux
gcc -o videofingerprinting videofringerprinting.c -lsqlite3 -lavutil -lavformat -lavcodec -lswscale -lz -lm -Wall
OSX
gcc -o videofingerprinting videofringerprinting.c -I/opt/local/include -L/opt/local/include -lsqlite3 -lavutil -lavformat -lavcodec -lswscale -lz -lm -Wall
*
To run:
./videofingerprint <mode> <video.mp4>
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

#define PI 3.1415926535897932384

int AvgFrame(AVFrame *pFrameFoo, int width, int height, int iFrame, char *filename, sqlite3 *handle, double fps);
int AvgFrameCentral(AVFrame *pFrameFoo, int width, int height, int iFrame, char *filename, sqlite3 *handle, double fps);
int AvgFrameImport(AVFrame *pFrameFoo, int width, int height, int iFrame, char *filename, sqlite3 *handle, double fps, int *fullArray);
int AvgFrameText(AVFrame *pFrameFoo, int width, int height, int iFrame, int key);
int cgo(AVFrame *pFrameFoo, int width, int height, int iFrame, char *filename, sqlite3 *handle);
int makeIndexes(int *shortArray, sqlite3 *handle, char *filename, int threshold, int size, double fps);

double prevY, prevU, prevV = 0.0;
int split = -1;
int split_second = 0;
int threshold = 5;

/*** 
Mode of operation:
*
0 = SUJ (SUJ with SQL)
1 = CGO (KAIST)
2 = SUJ (text) (default)
4 = SUJCentral (SUJ Central square with SQL)
***/
int mode = 0;

int main(int argc, char *argv[]) {

  if (argv[1] != NULL) {
	if (strcmp(argv[1], "-cgo") == 0) {
		printf("Using CGO\n");
		mode = 1;
	}
	
	if (strcmp(argv[1], "-suj") == 0) {
		printf("Using SUJ with SQL\n");
		mode = 0;
	}
	
	if (strcmp(argv[1], "-sujimport") == 0) {
		printf("Using SUJ Central with SQL\n");
		mode = 4;
	}
	
	if (strcmp(argv[1], "-sujcentral_cif") == 0) {
		printf("Using SUJ Central with SQL (cif)\n");
		mode = 14;
	}
	
	if (strcmp(argv[1], "-sujcentral_fps") == 0) {
		printf("Using SUJ Central with SQL (fps)\n");
		mode = 24;
	}
	
	if (strcmp(argv[1], "-sujcentral_brate") == 0) {
		printf("Using SUJ Central with SQL (brate)\n");
		mode = 34;
	}
	
	if (strcmp(argv[1], "-sujcentral_qcif") == 0) {
		printf("Using SUJ Central with SQL (qcif)\n");
		mode = 44;
	}
	
	if (strcmp(argv[1], "-sujcentral_5fps") == 0) {
		printf("Using SUJ Central with SQL (5fps)\n");
		mode = 54;
	}
	
	if (strcmp(argv[1], "-sujcentral_grey") == 0) {
		printf("Using SUJ Central with SQL (grey)\n");
		mode = 64;
	}
	
	if (strcmp(argv[1], "-sujcentral_rot1") == 0) {
		printf("Using SUJ Central with SQL (rot1)\n");
		mode = 71;
	}
	
	if (strcmp(argv[1], "-sujcentral_rot2") == 0) {
		printf("Using SUJ Central with SQL (rot2)\n");
		mode = 72;
	}
	
	if (strcmp(argv[1], "-sujcentral_rot3") == 0) {
		printf("Using SUJ Central with SQL (rot3)\n");
		mode = 73;
	}

	if (strcmp(argv[1], "-sujcentral_rot5") == 0) {
		printf("Using SUJ Central with SQL (rot5)\n");
		mode = 75;
	}
	
	if (strcmp(argv[1], "-sujcentral_rot7") == 0) {
		printf("Using SUJ Central with SQL (rot7)\n");
		mode = 77;
	}
	
	if (strcmp(argv[1], "-sujtext") == 0) {
		printf("Using SUJ with text output\n");
		mode = 2;
	}
  }
  
  //Find the last / in passed filename. 
  char *filename = strrchr(argv[2],'/') + 1;

  /*** DB initialization ***/
  int retval = 0;

  // Create a handle for database connection, create a pointer to sqlite3
  sqlite3 *handle;
  
  //Full array init of size 5h@60fps (a.k.a large enough)
  //TO FIX: use dynamic array?
  int *fullArray = (int*) calloc ( (1080000-1), sizeof (int));

  // try to create the database. If it doesnt exist, it would be created
  // pass a pointer to the pointer to sqlite3, in short sqlite3**
  if (mode == 1) {
	retval = sqlite3_open("/home/gsc/test_cgo_modelling_rot3.db",&handle);
	// If connection failed, handle returns NULL
	if(retval){
		printf("Database connection failed\n");
		return -1;
	}
  }
  else if (mode == 0) {
	retval = sqlite3_open("/home/gsc/test_suj_branch3_central.db",&handle);
	// If connection failed, handle returns NULL
	if(retval){
		printf("Database connection failed\n");
		return -1;
	}
  }  
  else if (mode == 4) {
	retval = sqlite3_open("/home/gsc/test_suj_branch3_import.db",&handle);
	// If connection failed, handle returns NULL
	if(retval){
		printf("Database connection failed\n");
		return -1;
	}
  }
  else if (mode == 14) {
	retval = sqlite3_open("/home/gsc/test_suj_branch2_central_cif.db",&handle);
	// If connection failed, handle returns NULL
	if(retval){
		printf("Database connection failed\n");
		return -1;
	}
  }
  else if (mode == 24) {
	retval = sqlite3_open("/home/gsc/test_suj_branch2_central_fps.db",&handle);
	// If connection failed, handle returns NULL
	if(retval){
		printf("Database connection failed\n");
		return -1;
	}
  }
  else if (mode == 34) {
	retval = sqlite3_open("/home/gsc/test_suj_branch2_central_brate.db",&handle);
	// If connection failed, handle returns NULL
	if(retval){
		printf("Database connection failed\n");
		return -1;
	}
  }
  else if (mode == 44) {
	retval = sqlite3_open("/home/gsc/test_suj_branch2_central_qcif.db",&handle);
	// If connection failed, handle returns NULL
	if(retval){
		printf("Database connection failed\n");
		return -1;
	}
  }
  else if (mode == 54) {
	retval = sqlite3_open("/home/gsc/test_suj_branch2_central_5fps.db",&handle);
	// If connection failed, handle returns NULL
	if(retval){
		printf("Database connection failed\n");
		return -1;
	}
  }
  else if (mode == 64) {
	retval = sqlite3_open("/home/gsc/test_suj_branch2_central_grey.db",&handle);
	// If connection failed, handle returns NULL
	if(retval){
		printf("Database connection failed\n");
		return -1;
	}
  }
  else if (mode == 71) {
	retval = sqlite3_open("/home/gsc/test_suj_branch2_central_rot1.db",&handle);
	// If connection failed, handle returns NULL
	if(retval){
		printf("Database connection failed\n");
		return -1;
	}
  }
  else if (mode == 72) {
	retval = sqlite3_open("/home/gsc/test_suj_branch2_central_rot2.db",&handle);
	// If connection failed, handle returns NULL
	if(retval){
		printf("Database connection failed\n");
		return -1;
	}
  }
  else if (mode == 73) {
	retval = sqlite3_open("/home/gsc/test_suj_branch2_central_rot3.db",&handle);
	// If connection failed, handle returns NULL
	if(retval){
		printf("Database connection failed\n");
		return -1;
	}
  }
  else if (mode == 75) {
	retval = sqlite3_open("/home/gsc/test_suj_branch2_central_rot5.db",&handle);
	// If connection failed, handle returns NULL
	if(retval){
		printf("Database connection failed\n");
		return -1;
	}
  }
  else if (mode == 77) {
	retval = sqlite3_open("/home/gsc/test_suj_branch2_central_rot7.db",&handle);
	// If connection failed, handle returns NULL
	if(retval){
		printf("Database connection failed\n");
		return -1;
	}
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
		sprintf(table_query,"create table '%s' (frame INTEGER, b1 FLOAT, b2 FLOAT, b3 FLOAT, b4 FLOAT, b5 FLOAT, b6 FLOAT, b7 FLOAT, b8 FLOAT);",filename);
	  } else if (mode == 0 ) {
		sprintf(table_query,"create table '%s' (s_end INTEGER, luma INTEGER, chromau INTEGER, chromav INTEGER);",filename);
	  } else if (mode == 4 || mode == 14 || mode == 24 || mode == 34 || mode == 44 || mode == 54 || mode == 64 || mode == 71 || mode == 72 || mode == 73 || mode == 75 || mode == 77) {
		sprintf(table_query,"create table '%s' (s_end FLOAT, luma INTEGER);",filename);
	  }
	  
	  retval = sqlite3_exec(handle,table_query,0,0,0);
	  if (retval) {
		char error [100];
		memset(error, 0, 100);
		sprintf(error,"Table for movie %s already exists!\n",filename);
		printf("%s",error);
		sqlite3_close(handle);
		return -1;
	  }
	  /*** DB init finished ***/
  }

  printf("Analyzing video %s\n",filename);

  av_register_all();
  
  AVFormatContext *pFormatCtx;

  // Open video file
  if(av_open_input_file(&pFormatCtx, filename, NULL, 0, NULL)!=0)
    return -1; // Couldn't open file
  
  // Retrieve stream information
  if(av_find_stream_info(pFormatCtx)<0)
    return -1; // Couldn't find stream information

  // Dump information about file onto standard error
  dump_format(pFormatCtx, 0, filename, 0);

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
  av_init_packet(&packet);
  struct SwsContext * sws_context;
  double fps = 0.0;

  if ( mode != 2) {
	  char allmovies_query[150];
	  memset(allmovies_query, 0, 150);
	  fps = (double)pFormatCtx->streams[videoStream]->r_frame_rate.num/(double)pFormatCtx->streams[videoStream]->r_frame_rate.den;
	  sprintf(allmovies_query, "insert into allmovies (name,fps) values ('%s',%d);", filename, (int)(fps*100));
	  retval = sqlite3_exec(handle,allmovies_query,0,0,0);
  }
  
  i=0;
  while(av_read_frame(pFormatCtx, &packet)>=0) {
  // Is this a packet from the video stream?
    if(packet.stream_index==videoStream) {
    // Decode video frame
      //avcodec_decode_video(pCodecCtx, pFrame, &frameFinished, packet.data, packet.size);
	  avcodec_decode_video2(pCodecCtx, pFrame, &frameFinished, &packet);
      
      // Did we get a video frame?
      if(frameFinished) {
        // Convert the image from its native format to YUV (PIX_FMT_YUV420P)
        //img_convert((AVPicture *)pFrameYUV, PIX_FMT_YUV420P, (AVPicture*)pFrame, pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height);
        //if (mode == 1) //CGO
		//	sws_context = sws_getContext(pCodecCtx->width, pCodecCtx->height, pCodecCtx->pix_fmt, 320, 240, PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);
		//else
			sws_context = sws_getContext(pCodecCtx->width, pCodecCtx->height, pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height, PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);
        
		sws_scale(sws_context, pFrame->data, pFrame->linesize, 0, pCodecCtx->height, pFrameYUV->data, pFrameYUV->linesize);
        sws_freeContext(sws_context);
		
		if (mode == 0)
			//retval = AvgFrame(pFrameYUV, pCodecCtx->width, pCodecCtx->height, i++, argv, handle, fps);
			retval = AvgFrame(pFrameYUV, pCodecCtx->width, pCodecCtx->height, i++, filename, handle, fps);
		else if (mode == 1)
			retval = cgo(pFrameYUV, pCodecCtx->width, pCodecCtx->height, i++, filename, handle);
			//retval = cgo(pFrameYUV, 320, 240, i++, argv, handle);
		else if (mode == 2)
			retval = AvgFrameText(pFrameYUV, pCodecCtx->width, pCodecCtx->height, i++, pFrame->key_frame);
		else if (mode == 4 || mode == 14 || mode == 24 || mode == 34 || mode == 44 || mode == 54 || mode == 64 || mode == 71 || mode == 72 || mode == 73 || mode == 75 || mode == 77)
			//retval = AvgFrameCentral(pFrameYUV, pCodecCtx->width, pCodecCtx->height, i++, argv, handle, fps);
			retval = AvgFrameImport(pFrameYUV, pCodecCtx->width, pCodecCtx->height, i++, filename, handle, fps, fullArray);
		else {
			printf("Please choose a mode!\n");
		}
      }
    }
  }
  
  //Cut the large fullArray to the movie actual size
  int *shortArray = (int*) calloc ( i, sizeof (int));
  memcpy(shortArray, fullArray, i*sizeof(int));
  free(fullArray);
  
  //Do magic
  makeIndexes(shortArray, handle, filename, threshold, i, fps);
  
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
  
  // Free full array
  free(shortArray);

  return 0;
  
}

int cgo(AVFrame *pFrame, int width, int height, int iFrame, char *filename, sqlite3* handle) {
  int y = 1;
  int x = 1;
  
  int M = 4;
  int N = 2;

  int i = 0;

  int **Gx;
  Gx = (int **) calloc ( (width-1), sizeof (int *));
  for (i=0; i<(width-1); ++i)
	Gx[i] = (int *) calloc ( (height-1), sizeof (int));
	
  int **Gy;
  Gy = (int **) calloc ( (width-1)*(height-1), sizeof (int *));
  for (i=0; i<(width-1); ++i)
	Gy[i] = (int *) calloc ( (height-1), sizeof (int));
	
  float a = 0.0;
  float b = 0.0;
  
  int j = 0;
  int k = 0;
  float cgo[M][N];
  memset(cgo, 0, M*N);
  
  int retval = 0;
	
  for(y = 1; y < (height-1); y++) {
	for (x = 1; x < (width-1); x++) {
		Gx[x][y] = pFrame->data[0][y*pFrame->linesize[0] + x + 1] - pFrame->data[0][y*pFrame->linesize[0] + x - 1];
		Gy[x][y] = pFrame->data[0][(y - 1)*pFrame->linesize[0] + x ] - pFrame->data[0][(y + 1)*pFrame->linesize[0] + x];
	}
  }
  
  //magnitude
  //r = sqrt(Gx[x]**2 + Gy[x]**2)
  //orientation
  //o = arctan(Gy[x]/Gx[x])
  
  //Iterate through each M*N block
  for (k = 0; k < N ; k++) { //row
	for (j = 0; j < M ; j++) { //column
		//printf("[%d][%d] (%d~%d),(%d~%d)\n",j,k,j*(width/M),(j+1)*(width/M),k*(height/N),(k+1)*(height/N));
		a = 0.0;
		b = 0.0;
		
		//Iterate through all the pixels of the smaller block
		for(y = (k*(height/N))+1; y < ((k+1)*((height-1)/N))+1; y++) {
			for (x = (j*(width/M))+1; x < ((j+1)*((width-1)/M))+1; x++) {
				if (Gx[x][y] == 0) {
					a+=Gy[x][y] * atan(PI/2);
				}
				else {
					a+=sqrt(Gx[x][y]*Gx[x][y] + Gy[x][y]*Gy[x][y])*atan(Gy[x][y]/Gx[x][y]);
				}
		
				b+=sqrt(Gx[x][y]*Gx[x][y] + Gy[x][y]*Gy[x][y]);
			}
		}

		//store the frame information in the bi-dimensional array cgo[M][N]
		//again: M=4, N=2
		if (b != 0)
			cgo[j][k] = a/b;
		
	}
  }
  
  for (i=0; i<(width-1); ++i) {
	free(Gx[i]);
	free(Gy[i]);
  }
  free(Gx);
  free(Gy);
  
  char blocks[200];
  memset(blocks, 0, 200);
  
  float kAvg = 0.0;
  float kStd = 0.0;
  
  for (k = 0; k < N  ; k++)
	for (j = 0; j < M ; j++)
		kAvg += cgo[j][k];

  kAvg /= (M*N);
  
  for (k = 0; k < N ; k++)
	for (j = 0; j < M ; j++)
		kStd += (cgo[j][k]-kAvg)*(cgo[j][k]-kAvg);

  kStd = sqrt(kStd/(M*N));
  
  //III A - Modelling
  
  for (k = 0; k < N ; k++) {
	for (j = 0; j < M ; j++) {
		if ( kStd != 0) {
			sprintf(blocks,"%s,%f",blocks,fabs((cgo[j][k] - kAvg)/kStd));
		}
		else {
			sprintf(blocks,"%s,%f",blocks,cgo[j][k]);
		}
	}
  }
  
  char insert_query[500];
  memset(insert_query, 0, 500);
  sprintf(insert_query, "insert into '%s' values (%d%s)",filename,iFrame,blocks);
  //printf("insert into '%s' values (%d%s)\n",filename,iFrame,blocks);
  
  retval = sqlite3_exec(handle,insert_query,0,0,0);
  
  if (retval)
	printf("%s\n",sqlite3_errmsg(handle));
  
  return retval;
}

int AvgFrame(AVFrame *pFrameFoo, int width, int height, int iFrame, char *filename, sqlite3* handle, double fps) {
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
		sprintf(table_query,"create table '%s_%d' (s_end INTEGER, luma INTEGER, chromau INTEGER, chromav INTEGER);",filename,split);
		sqlite3_exec(handle,table_query,0,0,0);
		sprintf(table_query,"insert into allmovies (name,fps) values ('%s_%d',%f);",filename,split,fps);
		sqlite3_exec(handle,table_query,0,0,0);
	}
  }
  
  char insert_query[500];
  memset(insert_query, 0, 500);
  //printf("%d;time;%f;%f;%f;%f\n", iFrame, avgLuma, fabs(avgLuma-prevY), avgChromaU, avgChromaV);
  if (split == 0) {
	sprintf(insert_query, "insert into '%s' values (%d,%f,%f,%f)",filename,iFrame,avgLuma,avgChromaU,avgChromaV);
  }
  else {
    sprintf(insert_query, "insert into '%s_%d' values (%d,%f,%f,%f)",filename,split,iFrame-split_second,avgLuma,avgChromaU,avgChromaV);
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

int AvgFrameCentral(AVFrame *pFrameFoo, int width, int height, int iFrame, char *filename, sqlite3* handle, double fps) {
  int y = 0;
  int x = 0;
  
  int M = 3;
  int N = 3;
  
  int retval = 0;
  
  unsigned int luma = 0;
  //unsigned int chromaV = 0;
  //unsigned int chromaU = 0;
  //float avgChromaU = 0.0;
  float avgLuma = 0.0;
  //float avgChromaV = 0.0;
  
  char table_query[150];
  
  int max_hours = 3;
  int max_frames = max_hours*60*60*fps;
  
  //printf("Averaging [%d][%d][%d][%d] of the original [0][0][%d][%d]\n", width/M, height/N,2*width/M ,2*height/N , width, height);
  
  for(y=height/N; y<2*height/N; y++){
    for (x=width/M; x<2*width/M; x++) {
	  //printf("Luma[%d][%d] %d\n", x, y, pFrameFoo->data[0][y*pFrameFoo->linesize[0] + x]);
	  //fflush(stdout);
      luma += pFrameFoo->data[0][y*pFrameFoo->linesize[0] + x];
    }
  }
  
/*  
  for(y=height/N; y<2*height/N; y++){
    for (x=width/M; x<2*width/M; x++) {
	  //printf("Chromas[%d][%d] %d %d\n", x, y, pFrameFoo->data[2][y*pFrameFoo->linesize[2] + x], pFrameFoo->data[1][y*pFrameFoo->linesize[1] + x]);
	  //fflush(stdout);
      chromaU += pFrameFoo->data[2][y*pFrameFoo->linesize[2] + x];
      chromaV += pFrameFoo->data[1][y*pFrameFoo->linesize[1] + x];
    }
  }
*/
  avgLuma = luma*1.0 / ((height*width)/((N+M)/2));
  //avgLuma = luma*1.0 / ((height*width)/(M*N));
//  avgChromaU = chromaU*1.0 / ((height*width)/N);
//  avgChromaV = chromaV*1.0 / ((height*width)/N);
  
  //Splitting large files into several files if larger than max_frames = max_hours*60*60*fps
  if ( (iFrame%max_frames) == 0 ) {
    printf("split++ (%d->%d) at frame %d (%d)\n",split,split+1,iFrame,split_second);
	split_second = iFrame;
	split++;
	if (split != 0) {
		sprintf(table_query,"create table '%s_%d' (s_end INTEGER, luma INTEGER);",filename,split);
		sqlite3_exec(handle,table_query,0,0,0);
		sprintf(table_query,"insert into allmovies (name,fps) values ('%s_%d',%f);",filename,split,fps);
		sqlite3_exec(handle,table_query,0,0,0);
	}
  }
  
  char insert_query[500];
  memset(insert_query, 0, 500);
  //printf("%d;time;%f;%f;%f;%f\n", iFrame, avgLuma, fabs(avgLuma-prevY), avgChromaU, avgChromaV);
  if (split == 0) {
	sprintf(insert_query, "insert into '%s' values (%d,%f)",filename,iFrame,avgLuma);
  }
  else {
    sprintf(insert_query, "insert into '%s_%d' values (%d,%f)",filename,split,iFrame-split_second,avgLuma);
  }

  retval = sqlite3_exec(handle,insert_query,0,0,0);
  
  if (retval)
	printf("%s\n",sqlite3_errmsg(handle));
  
  prevY = avgLuma;
  //prevU = avgChromaU;
  //prevV = avgChromaV;
  
  return retval;
}

int AvgFrameImport(AVFrame *pFrameFoo, int width, int height, int iFrame, char *filename, sqlite3* handle, double fps, int *fullArray) {
  int y = 0;
  int x = 0;
  
  int M = 3;
  int N = 3;
  
  unsigned int luma = 0;
  float avgLuma = 0.0;
  
  //printf("Averaging [%d][%d][%d][%d] of the original [0][0][%d][%d]\n", width/M, height/N,2*width/M ,2*height/N , width, height);
  
  for(y=height/N; y<2*height/N; y++)
    for (x=width/M; x<2*width/M; x++)
      luma += pFrameFoo->data[0][y*pFrameFoo->linesize[0] + x];
  
  avgLuma = luma*1.0 / ((height*width)/((N+M)/2));
  
  //Insert every frame into a bidimensional array
  fullArray[iFrame] = (int)(avgLuma*100);
  //printf("%d\n",(int)(avgLuma*100));
  
  prevY = avgLuma;
  
  return 0;
};

int makeIndexes(int *shortArray, sqlite3* handle, char *filename, int threshold, int size, double fps) {

  int aux = 0;
  //float first = 0.0f;
  //Up-down fix
  int first = shortArray[0];
  int avgLuma = 0;
  int thresh = threshold * 100;
  int retval = 0;
  char insert_query[500];
  int counter = 1;
  
  //For each frame of the movie
  for (aux = 0 ; aux < size ; aux++) {
    avgLuma += shortArray[aux];
	//printf("avgL=%d frameL=%d counter=%d time=%f\n",avgLuma/counter, shortArray[aux], counter, aux/fps);
	
	//If the current value is above of below the threshold and if we're not at the first frame, make a new index
	//if ( (shortArray[aux] < ((avgLuma/counter)-thresh) || shortArray[aux] > ((avgLuma/counter)+thresh)) ) {
	//Up-down fix
	if ( (shortArray[aux] < (first-thresh) || shortArray[aux] > (first+thresh)) ) {
	  
	  //Update the database
      memset(insert_query, 0, 500);
      sprintf(insert_query, "insert into '%s' values (%f,%d)",filename,aux/fps,first);
      retval = sqlite3_exec(handle,insert_query,0,0,0);
  
      if (retval)
	    printf("%s\n",sqlite3_errmsg(handle));
		
      //Update values for next index
	  avgLuma = 0;
      counter = 1;
	  //first = aux/fps;
	  //Up-down fix
	  first = shortArray[aux+1];
	}
	else
	  counter++;
  }
  // Last entry
  memset(insert_query, 0, 500);
  sprintf(insert_query, "insert into '%s' values (%f,%d)",filename,aux/fps,-1);
  retval = sqlite3_exec(handle,insert_query,0,0,0);
  
  if (retval)
	printf("%s\n",sqlite3_errmsg(handle));
  
  return retval;
}