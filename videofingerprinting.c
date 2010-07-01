/******
*
Based on FFMpeg Tutorial
http://www.dranger.com/ffmpeg/tutorial01.html
*
To compile:
Linux
gcc -o videofingerprinting videofringerprinting.c -static -lsqlite3 -lavutil -lavformat -lavcodec -lswscale -lz -lm -Wall
OSX
gcc -o videofingerprinting videofringerprinting.c -I/opt/local/include -L/opt/local/lib -lsqlite3 -lavutil -lavformat -lavcodec -lswscale -lz -lm -Wall
Static
gcc -o videofingerprinting videofringerprinting.c -static -lsqlite3 -lavformat -lavcodec -lswscale -lavutil -lpthread -lbz2 -lfaac -lfaad -lmp3lame -lvorbisenc -lvorbis -logg -lx264 -lxvidcore -lz -lm -lc -Wall -m32
*
To run:
./videofingerprint <{path/to/}video.mp4> || - <filename> >  <sqlite_file.db>
Where commands inside {} are facultative and || denotes either the left or right part needs to be input
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
int AvgFrameImport(AVFrame *pFrameFoo, int width, int height, int iFrame, char *filename, sqlite3 *handle, double fps, int *fullArray);
static int sqlite_makeindexes_callback(void *newinfo, int argc, char **argv, char **azColName);
static int sqlite_mid_callback(void *newinfo, int argc, char **argv, char **azColName);
int makeIndexes(int *shortArray, sqlite3 *handle, char *filename, int threshold, int size, double fps);

double prevY, prevU, prevV = 0.0;
int split = -1;
int split_second = 0;
int threshold = 5;

int main(int argc, char *argv[]) {
  
  char *filename = NULL;
  char *inputsource = NULL;
  char *outputDB = NULL;
  
  //Find the last / in passed filename.
  if (strrchr(argv[1],'/') == NULL) {
    if (strcmp(argv[1],"-") == 0) {
	  inputsource = "/dev/stdin";
	  if (argv[2] == NULL) {
	    printf("Please input a name for the movie!\n");
		return -1;
	  } else {
	    if (strrchr(argv[2],'/') == NULL)
		  filename = argv[2];
		else
		  filename = strrchr(argv[2],'/') + 1;
	  }
	} else {
	  filename = argv[1];
	
	  if (argv[2] != NULL && argc == 3) {
        outputDB = argv[2];
      } else {
        outputDB = "/tmp/videofingerprint.db";
      }
	}
  } else {
	filename = strrchr(argv[1],'/') + 1;
	if (argv[3] != NULL && argc == 4) {
	  outputDB = argv[3];
    } else {
      outputDB = "/tmp/videofingerprint.db";
    }
  }
  inputsource = argv[1];
  

  
  printf("Filename = %s Input source = %s DB output = %s argc = %d\n",filename,inputsource,outputDB, argc);

  /*** DB initialization ***/
  int retval = 0;

  // Create a handle for database connection, create a pointer to sqlite3
  sqlite3 *handle;
  
  //Full array init of size 5h@60fps (a.k.a large enough)
  //TO FIX: use dynamic array?
  int *fullArray = (int*) calloc ( (1080000-1), sizeof (int));

  // try to create the database. If it doesnt exist, it would be created
  // pass a pointer to the pointer to sqlite3, in short sqlite3**

  retval = sqlite3_open(outputDB,&handle);
  // If connection failed, handle returns NULL
  if(retval){
	printf("Database connection failed\n");
	return -1;
  }
  
  char query1[] = "create table allmovies (allmovieskey INTEGER PRIMARY KEY,name TEXT,fps INTEGER);";
  // Execute the query for creating the table
  retval = sqlite3_exec(handle,query1,0,0,0);
  char query2[] = "PRAGMA count_changes = OFF";
  retval = sqlite3_exec(handle,query2,0,0,0);
  char query3[] = "PRAGMA synchronous = OFF";
  retval = sqlite3_exec(handle,query3,0,0,0);
  
  //Hashluma table
  char query_hash[] = "create table hashluma (avg_range int, movies TEXT)";
  retval = sqlite3_exec(handle,query_hash,0,0,0);
  
  if (!retval) {
    //Populating the hash tables
	printf("Populating hashluma table\n");
    char hashquery[50];
    memset(hashquery, 0, 50);
    int i = 0;
    for(i=0; i <= 254; i++) {
	  sprintf(hashquery, "insert into hashluma (avg_range) values (%d)", i);
	  retval = sqlite3_exec(handle,hashquery,0,0,0);
    }
  }
  
  char table_query[150];
  memset(table_query, 0, 150);
  sprintf(table_query,"create table '%s' (s_end FLOAT, luma INTEGER);",filename);
  
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

  printf("Analyzing video %s\n",filename);

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

  char allmovies_query[150];
  memset(allmovies_query, 0, 150);
  fps = (double)pFormatCtx->streams[videoStream]->r_frame_rate.num/(double)pFormatCtx->streams[videoStream]->r_frame_rate.den;
  sprintf(allmovies_query, "insert into allmovies (name,fps) values ('%s',%d);", filename, (int)(fps*100));
  retval = sqlite3_exec(handle,allmovies_query,0,0,0);
  
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
		sws_context = sws_getContext(pCodecCtx->width, pCodecCtx->height, pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height, PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);
        
		sws_scale(sws_context, pFrame->data, pFrame->linesize, 0, pCodecCtx->height, pFrameYUV->data, pFrameYUV->linesize);
        sws_freeContext(sws_context);
		
		retval = AvgFrameImport(pFrameYUV, pCodecCtx->width, pCodecCtx->height, i++, filename, handle, fps, fullArray);
		
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
  
  //BUG on first equation
  avgLuma = luma*1.0 / ((height*width)/((N+M)/2));
  //avgLuma = luma*1.0 / ((height/N)*(width/M));
  
  //Insert every frame into a bidimensional array
  fullArray[iFrame] = (int)(avgLuma*100);
  //printf("%d\n",(int)(avgLuma*100));
  
  prevY = avgLuma;
  
  return 0;
};

static int sqlite_makeindexes_callback(void *info, int argc, char **argv, char **azColName){
    //FIX: make info dynamic!
	memset((char *)info, 0, 500000);
    int i;
    for(i=0; i<argc; i++){
      //printf("%s = %s\n", azColName[i], argv[i] ? argv[i]: "NULL");
	  sprintf(info, "%s", argv[i] ? argv[i]: "");
    }
    return 0;
}

static int sqlite_mid_callback(void *mid, int argc, char **argv, char **azColName){
	memset((char *)mid, 0, 50);
    int i;
    for(i=0; i<argc; i++){
      //printf("%s = %s\n", azColName[i], argv[i] ? argv[i]: "NULL");
	  sprintf(mid, "%s", argv[i] ? argv[i]: "NULL");
    }
    return 0;
}

int makeIndexes(int *shortArray, sqlite3* handle, char *filename, int threshold, int size, double fps) {

  int aux = 0;
  //float first = 0.0f;
  //Up-down fix
  int first = shortArray[0];
  double prev = 0;
  int avgLuma = 0;
  int thresh = threshold * 100;
  int retval = 0;
  char insert_query[500000];
  char select_query[500000];
  char info[500000];
  char newinfo[500000];
  char mid[50];
  int counter = 1;
  
  memset(info, 0, 500000);
  memset(newinfo, 0, 500000);
  memset(insert_query, 0, 500000);
  memset(select_query, 0, 500000);
  memset(mid, 0, 50);
  
  //Get movie id
  memset(select_query, 0, 500000);
  sprintf(select_query, "select allmovieskey from allmovies where name = \"%s\"", filename );
  retval = sqlite3_exec(handle,select_query,sqlite_mid_callback,mid,NULL);
	  
  //printf("Movie %s MID is %s\n", filename, mid);
  
  if (retval)
	printf("%s\n",sqlite3_errmsg(handle));
  
  //For each frame of the movie
  for (aux = 0 ; aux < size ; aux++) {
    //printf("aux=%d\n", aux);
	//fflush(stdout);
    avgLuma += shortArray[aux];
	//printf("avgL=%d frameL=%d counter=%d time=%f\n",avgLuma/counter, shortArray[aux], counter, aux/fps);
	
	//If the current value is above of below the threshold and if we're not at the first frame, make a new index
	//if ( (shortArray[aux] < ((avgLuma/counter)-thresh) || shortArray[aux] > ((avgLuma/counter)+thresh)) ) {
	//Up-down fix
	if ( (shortArray[aux] < (first-thresh) || shortArray[aux] > (first+thresh)) ) {
	  
	  //Update the movie database
      memset(insert_query, 0, 500000);
      sprintf(insert_query, "insert into '%s' values (%f,%d)",filename,aux/fps,first);
      retval = sqlite3_exec(handle,insert_query,0,0,0);
	  
      if (retval)
	    printf("%s\n",sqlite3_errmsg(handle));
			  
	  //Get previous hash info
	  memset(select_query, 0, 500000);
	  sprintf(select_query, "select movies from hashluma where avg_range = \"%d\"", first/100);
	  retval = sqlite3_exec(handle,select_query,sqlite_makeindexes_callback,info,NULL);

      if (retval)
	    printf("%s\n",sqlite3_errmsg(handle));
		
	  //Update the hashtable
	  //FIX: make newinfo dynamic!
	  memset(newinfo, 0, 500000);
	  sprintf(newinfo, "%s%s:%f-%f,", info, mid, prev, aux/fps);
	  //printf("%s\n", newinfo);
	  
	  sprintf(insert_query, "update hashluma set movies = \"%s\" where avg_range = \"%d\"", newinfo, first/100);
      retval = sqlite3_exec(handle,insert_query,0,0,0);
  
      if (retval)
	    printf("%s\n",sqlite3_errmsg(handle));
		
      //Update values for next index
	  avgLuma = 0;
      counter = 1;
	  //first = aux/fps;
	  //Up-down fix
	  first = shortArray[aux+1];
	  prev = aux/fps;
	}
	else
	  counter++;
  }
  // Last entry
  memset(insert_query, 0, 500000);
  sprintf(insert_query, "insert into '%s' values (%f,%d)",filename,aux/fps,-1);
  retval = sqlite3_exec(handle,insert_query,0,0,0);
  
  if (retval)
	printf("%s\n",sqlite3_errmsg(handle));
  
  return retval;
}