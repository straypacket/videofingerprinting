/******
*
Based on FFMpeg Tutorial
http://www.dranger.com/ffmpeg/tutorial01.html
*
To compile:
Linux
gcc -o videofingerprinting_pg videofingerprinting_pg.c -lsqlite3 -lavutil -lavformat -lavcodec -lswscale -lz -lm -Wall
OSX
gcc -o videofingerprinting_pg videofingerprinting_pg.c -I/opt/local/include -I/opt/local/include/postgresql84/ -L/opt/local/lib -L/opt/local/lib/postgresql84/ -lpq -lavutil -lavformat -lavcodec -lswscale -lz -lm -Wall
Static
gcc -o videofingerprinting_pg videofingerprinting_pg.c -static -lsqlite3 -lavformat -lavcodec -lswscale -lavutil -lpthread -lbz2 -lfaac -lfaad -lmp3lame -lvorbisenc -lvorbis -logg -lx264 -lxvidcore -lz -lm -lc -Wall -m32
*
To run:
./videofingerprint < {path/to/}video.mp4> || - <filename> >
Where commands inside {} are facultative and || denotes either the left or right part needs to be input
******/
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <math.h>
#include <time.h>
#include <sys/time.h>
#include <string.h>
/** DB stuff **/
#include <stdio.h>
#include <libpq-fe.h>
#include <stdlib.h>

#define PI 3.1415926535897932384
int AvgFrameImport(AVFrame *pFrameFoo, int width, int height, int iFrame, char *filename, PGconn *handle, double fps, int *fullArray);
int AvgFullFrameImport(AVFrame *pFrameFoo, int width, int height, int iFrame, char *filename, PGconn *handle, double fps, int *fullArray);
int makeIndexes(int *shortArray, PGconn *handle, char *filename, int threshold, int size, double fps);

double prevY, prevU, prevV = 0.0;
int split = -1;
int split_second = 0;
// ============
// DB Threshold
// ============
int threshold = 6;

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
	    if (strrchr(argv[2],'/') == NULL) {
		  filename = argv[2];
		} else {
		  filename = strrchr(argv[2],'/') + 1;
		}
		  
		if (argv[3] != NULL && argc == 4) {
	      outputDB = argv[3];
        } else {
          outputDB = "videofingerprint";
        }
		
	  }
	} else {
	  filename = argv[1];
	  inputsource = argv[1];
	
	  if (argv[2] != NULL && argc == 3) {
        outputDB = argv[2];
      } else {
        outputDB = "videofingerprint";
      }
	}
  } else {
	filename = strrchr(argv[1],'/') + 1;
	inputsource = argv[1];
	
	if (argv[2] != NULL && argc == 3) {
	  outputDB = argv[2];
    } else {
      outputDB = "videofingerprint";
    }
  }
  
  printf("Filename = %s Input source = %s argc = %d\n",filename,inputsource, argc);

  /*** DB initialization ***/
  int retval = 0;

  // Create a handle for database connection
  PGconn *handle = PQconnectdb("dbname=videofingerprint host=192.168.4.135 user=skillup password='skillupjapan'");

  if (PQstatus(handle) != CONNECTION_OK) {
      fprintf(stderr, "Connection to database failed: %s", PQerrorMessage(handle));
      PQfinish(handle);
      exit(1);
  }
  
  PGresult *result = NULL;

  //Full array init of size 30h@60fps (a.k.a large enough)
  //TO FIX: use dynamic array?
  int *fullArray = (int*) calloc ( (6480000-1), sizeof (int));
  
  char query1[] = "create table allmovies (allmovieskey serial PRIMARY KEY UNIQUE, name TEXT, fps INTEGER, date INTEGER, audio_fp INTEGER[], video_fp NUMERIC[][], diff_video_fp NUMERIC[][])";
  // Execute the query for creating the table
  result = PQexecParams(handle,query1,0,NULL,NULL,NULL,NULL,1);
  if (PQresultStatus(result) != PGRES_COMMAND_OK) {
      fprintf(stderr, "Table allmovies already exists, continuing ... \n");
  }
  PQclear(result);

  //DiffHashluma table
  char query_hash[] = "create table diffhashluma (diff_range_1 int, diff_range_2 int, movies NUMERIC[][])";
  result = PQexecParams(handle,query_hash,0,NULL,NULL,NULL,NULL,1);
  if (PQresultStatus(result) != PGRES_COMMAND_OK) {
      fprintf(stderr, "Table diffhashluma already exists, continuing ... \n");
  } else {
    //Populating the hash tables
    printf("Populating diffhashluma table\n");
    int i,j = 0;
    char hashquery[100];
    memset(hashquery, 0, 100);
    for(i=0; i <= 254; i++) {
      for(j=0; j <= 254; j++) {
	sprintf(hashquery, "insert into diffhashluma (diff_range_1, diff_range_2, movies) values (%d, %d, '{{0.0,0.0,0.0}}')", i, j);
	result = PQexecParams(handle,hashquery,0,NULL,NULL,NULL,NULL,1);
        if (PQresultStatus(result) != PGRES_COMMAND_OK) {
           fprintf(stderr, "%s failed: %s", hashquery, PQerrorMessage(handle));
           PQclear(result);
           PQfinish(handle);
           exit(1);
        }
      }
    }
  }
  PQclear(result);

  //Hashluma table
  char query_hash1[] = "create table hashluma (avg_range_1 int, avg_range_2 int, movies NUMERIC[][])";
  result = PQexecParams(handle,query_hash1,0,NULL,NULL,NULL,NULL,1);
  if (PQresultStatus(result) != PGRES_COMMAND_OK) {
      fprintf(stderr, "Table hashluma already exists, continuing ... \n");
  } else {
    //Populating the hash tables
    printf("Populating hashluma table\n");
    int i,j = 0;
    char hashquery1[100];
    memset(hashquery1, 0, 100);
    for(i=0; i <= 254; i++) {
      for(j=0; j <= 254; j++) {
	sprintf(hashquery1, "insert into hashluma (avg_range_1,avg_range_2,movies) values (%d,%d,'{{0.0,0.0,0.0}}')", i, j);
	result = PQexecParams(handle,hashquery1,0,NULL,NULL,NULL,NULL,1);
        if (PQresultStatus(result) != PGRES_COMMAND_OK) {
          fprintf(stderr, "%s failed: %s", hashquery1, PQerrorMessage(handle));
          PQclear(result);
          PQfinish(handle);
          exit(1);
        }
      }
    }
  }
  PQclear(result);
  
  /*** DB init finished ***/

  char rec_query[150];
  memset(rec_query, 0, 150);
  sprintf(rec_query,"select name from allmovies where name='%s'",filename);
  result = PQexecParams(handle,rec_query,0,NULL,NULL,NULL,NULL,1);

  if (PQresultStatus(result) == PGRES_NONFATAL_ERROR) {
	fprintf(stderr, "%s failed: %s", rec_query, PQerrorMessage(handle));
        PQclear(result);
        PQfinish(handle);
        exit(1);
  }

  //Decide which is the best policy, not FP? overwrite? new file?
  if (PQntuples(result) != 0) {
	char error[150];
        memset(error, 0, 150);
	sprintf(error,"Data for movie %s already exists! Skipping fingerprinting ... \n",filename);
	printf("%s",error);
        PQclear(result);
        PQfinish(handle);
        exit(1);
  }

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
    PQfinish(handle);
    exit(1);
  }
  // Open codec
  if(avcodec_open(pCodecCtx, pCodec)<0) {
    PQfinish(handle);
    exit(1);
  }

  AVFrame *pFrame;
  AVFrame *pFrameYUV;

  // Allocate video frame
  pFrame=avcodec_alloc_frame();
  
  // Allocate an AVFrame structure
  pFrameYUV=avcodec_alloc_frame();
  if(pFrameYUV==NULL) {
    PQfinish(handle);
    exit(1);
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
  struct SwsContext* sws_context;
  double fps = 0.0;
  
  struct timeval tv;
  gettimeofday(&tv, NULL);

  char allmovies_query[150];
  memset(allmovies_query, 0, 150);
  fps = (double)pFormatCtx->streams[videoStream]->r_frame_rate.num/(double)pFormatCtx->streams[videoStream]->r_frame_rate.den;
  sprintf(allmovies_query, "insert into allmovies (name,fps,date) values ('%s',%d,%d);", filename, (int)(fps*100), (int)tv.tv_sec);
  result = PQexecParams(handle,allmovies_query,0,NULL,NULL,NULL,NULL,1);
  if (PQresultStatus(result) != PGRES_COMMAND_OK) {
      fprintf(stderr, "INSERT into allmovies failed: %s", PQerrorMessage(handle));
      PQfinish(handle);
      exit(1);
  }
  PQclear(result);
  
  // Initialize context
  //TO DO:
  //sws_context->srcFormat = pCodecCtx->pix_fmt;
  //sws_context->dstFormat = PIX_FMT_YUV420P;
  //sws_context->srcW = pCodecCtx->width;
  //sws_context->srcH = pCodecCtx->height;
  //sws_context->dstW = pCodecCtx->width;
  //sws_context->dstH = pCodecCtx->height;
  //sws_context->flags = SWS_FAST_BILINEAR;
		  
  i=0;
  while(av_read_frame(pFormatCtx, &packet)>=0) {
  // Is this a packet from the video stream?
    if(packet.stream_index==videoStream) {
    // Decode video frame
      //avcodec_decode_video(pCodecCtx, pFrame, &frameFinished, packet.data, packet.size);
	  avcodec_decode_video2(pCodecCtx, pFrame, &frameFinished, &packet);
      
      // Did we get a video frame?
      if(frameFinished) {
	    if (pCodecCtx->pix_fmt != PIX_FMT_YUV420P) {
          // Convert the image from its native format to YUV (PIX_FMT_YUV420P)

		  // TO DO
		  //sws_init_context(sws_context, NULL, NULL);
 		  sws_context = sws_getContext(pCodecCtx->width, pCodecCtx->height, pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height, PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);
          
		  sws_scale(sws_context, pFrame->data, pFrame->linesize, 0, pCodecCtx->height, pFrameYUV->data, pFrameYUV->linesize);
                  sws_freeContext(sws_context);
		  
		  retval = AvgFrameImport(pFrameYUV, pCodecCtx->width, pCodecCtx->height, i++, filename, handle, fps, fullArray);
		} else {
		  retval = AvgFrameImport(pFrame, pCodecCtx->width, pCodecCtx->height, i++, filename, handle, fps, fullArray);
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
  PQfinish(handle);
  
  // Free full array
  free(shortArray);

  return 0;
}

int AvgFullFrameImport(AVFrame *pFrameFoo, int width, int height, int iFrame, char *filename, PGconn* handle, double fps, int *fullArray) {
  int y = 0;
  int x = 0;
  
  unsigned int luma = 0;
  float avgLuma = 0.0;
  
  //printf("Averaging [%d][%d][%d][%d] of the original [0][0][%d][%d]\n", width/M, height/N,2*width/M ,2*height/N , width, height);
  
  for(y=0; y<height; y++)
    for (x=0; x<width; x++)
      luma += pFrameFoo->data[0][y*pFrameFoo->linesize[0] + x];
  
  avgLuma = luma*1.0 / (height*width);
  //avgLuma = luma*1.0 / ((height/N)*(width/M));
  
  //Insert every frame into a bidimensional array
  fullArray[iFrame] = (int)(avgLuma*100);
  //printf("%d\n",(int)(avgLuma*100));
  
  prevY = avgLuma;
  
  return 0;
  
}

int AvgFrameImport(AVFrame *pFrameFoo, int width, int height, int iFrame, char *filename, PGconn* handle, double fps, int *fullArray) {
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
  //avgLuma = luma*1.0 / ((height*width)/((N+M)/2));
  avgLuma = luma*1.0 / ((height/N)*(width/M));
  
  //Insert every frame into a bidimensional array
  fullArray[iFrame] = (int)(avgLuma*100);
  //printf("%d\n",(int)(avgLuma*100));
  
  prevY = avgLuma;
  
  return 0;
  
};

int makeIndexes(int *shortArray, PGconn* handle, char *filename, int threshold, int size, double fps) {

  int aux = 0;
  int first = shortArray[0];
  double prev = 0;
  double prev_luma = 0;
  double diff_prev_luma = 0;
  int avgLuma = 0;
  int thresh = threshold * 100;
  int retval = 0;
  char insert_query[500000];
  char update_query[500000];
  char select_query[500000];
  char info[500000];
  char newinfo[500000];
  int mid = 0;
  int counter = 1;

  PGresult *result = NULL;
  
  memset(info, 0, 500000);
  memset(newinfo, 0, 500000);
  memset(insert_query, 0, 500000);
  memset(update_query, 0, 500000);
  memset(select_query, 0, 500000);
  
  //Get movie id
  memset(select_query, 0, 500000);
  sprintf(select_query, "select allmovieskey from allmovies where name='%s'", filename );
  result = PQexecParams(handle,select_query,0,NULL,NULL,NULL,NULL,1);

  if (PQresultStatus(result) == PGRES_NONFATAL_ERROR) {
	fprintf(stderr, "%s failed: %s\n", select_query, PQerrorMessage(handle));
        PQclear(result);
        PQfinish(handle);
        exit(1);
  }

  char *v;
  v = PQgetvalue(result,0,0);
  mid = ntohl(*((uint32_t *) v));
  //printf("Movie %s MID is %d\n", filename, mid);

  //Initialize bidimensional arrays
  memset(update_query, 0, 500000);
  sprintf(update_query, "update allmovies set video_fp='{{0.0,0}}' where name='%s'", filename );
  result = PQexecParams(handle,update_query,0,NULL,NULL,NULL,NULL,1);

  if (PQresultStatus(result) != PGRES_COMMAND_OK) {
	fprintf(stderr, "%s failed: %s\n", update_query, PQerrorMessage(handle));
        PQclear(result);
        PQfinish(handle);
        exit(1);
  }

  memset(update_query, 0, 500000);
  sprintf(update_query, "update allmovies set diff_video_fp='{{0.0,0}}' where name='%s'", filename );
  result = PQexecParams(handle,update_query,0,NULL,NULL,NULL,NULL,1);

  if (PQresultStatus(result) != PGRES_COMMAND_OK) {
	fprintf(stderr, "%s failed: %s\n", update_query, PQerrorMessage(handle));
        PQclear(result);
        PQfinish(handle);
        exit(1);
  }


  //For each frame of the movie
  for (aux = 0 ; aux < size ; aux++) {
      avgLuma += shortArray[aux];
      //printf("avgL=%d frameL=%d counter=%d time=%f\n",avgLuma/counter, shortArray[aux], counter, aux/fps);
      //printf("%d\t%d\t%f\n",avgLuma/counter, shortArray[aux], aux/fps);    
	
      //If the current value is above of below the threshold and if we're not at the first frame, make a new index
      if ( (shortArray[aux] < (first-thresh) || shortArray[aux] > (first+thresh)) ) {
	  
	  //Update the movie database
	  //Value of jump
          memset(update_query, 0, 500000);
          sprintf(update_query, "UPDATE allmovies SET video_fp=(SELECT array_cat((SELECT video_fp FROM allmovies WHERE name='%s'),ARRAY[%f,%d])) WHERE name='%s'",filename,aux/fps,first,filename);
          result = PQexecParams(handle,update_query,0,NULL,NULL,NULL,NULL,1);

          if (PQresultStatus(result) != PGRES_COMMAND_OK) {
  	      fprintf(stderr, "%s failed: %s\n", update_query, PQerrorMessage(handle));
              PQclear(result);
              PQfinish(handle);
              exit(1);
          }
	  //Difference between jumps
          memset(update_query, 0, 500000);
          sprintf(update_query, "UPDATE allmovies SET diff_video_fp=(SELECT array_cat((SELECT video_fp FROM allmovies WHERE name='%s'),ARRAY[%f,%d])) WHERE name='%s'",filename,aux/fps,abs(first-shortArray[aux]),filename);
          result = PQexecParams(handle,update_query,0,NULL,NULL,NULL,NULL,1);

          if (PQresultStatus(result) != PGRES_COMMAND_OK) {
  	      fprintf(stderr, "%s failed: %s\n", update_query, PQerrorMessage(handle));
              PQclear(result);
              PQfinish(handle);
              exit(1);
          }

	  //Update the diffhashluma database
	  memset(update_query, 0, 500000);
	  sprintf(update_query, "UPDATE diffhashluma SET movies=(SELECT array_cat((SELECT movies FROM diffhashluma WHERE diff_range_1='%d' AND diff_range_2='%d'),ARRAY[%d,%f,%f])) WHERE diff_range_1 = '%d' AND diff_range_2 = '%d'", (int)diff_prev_luma, (int)abs((first/100)-(shortArray[aux]/100)), mid, prev, aux/fps, (int)diff_prev_luma, (int)abs((first/100)-(shortArray[aux]/100)));
          result = PQexecParams(handle,update_query,0,NULL,NULL,NULL,NULL,1);

          if (PQresultStatus(result) != PGRES_COMMAND_OK) {
  	      fprintf(stderr, "%s failed: %s\n", update_query, PQerrorMessage(handle));
              PQclear(result);
              PQfinish(handle);
              exit(1);
          }

	  //Update the hashluma database
	  memset(update_query, 0, 500000);
	  sprintf(update_query, "UPDATE hashluma SET movies=(SELECT array_cat((SELECT movies FROM hashluma WHERE avg_range_1='%d' AND avg_range_2='%d'),ARRAY[%d,%f,%f])) WHERE avg_range_1 = '%d' AND avg_range_2 = '%d'", (int)prev_luma, (int)first/100, mid, prev, aux/fps, (int)prev_luma, (int)first/100);
          result = PQexecParams(handle,update_query,0,NULL,NULL,NULL,NULL,1);

          if (PQresultStatus(result) != PGRES_COMMAND_OK) {
  	      fprintf(stderr, "%s failed: %s\n", update_query, PQerrorMessage(handle));
              PQclear(result);
              PQfinish(handle);
              exit(1);
          }
		
          //Update values for next index
	  avgLuma = 0;
          counter = 1;
	  diff_prev_luma = abs((first/100)-(shortArray[aux]/100));
	  prev_luma = abs(first/100);
	  first = shortArray[aux+1];
	  prev = aux/fps;
      } else
	  counter++;
  }
  // Last entry
  memset(insert_query, 0, 500000);
  sprintf(insert_query, "insert into '%s' values (%f,%d)",filename,aux/fps,-1);
  //!//retval = sqlite3_exec(handle,insert_query,0,0,0);
  
  //!//if (retval)
	//!//printf("%s\n",sqlite3_errmsg(handle));
  
  return retval;
}
