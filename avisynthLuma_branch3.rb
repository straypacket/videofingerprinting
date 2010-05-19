#Usage
#avisynthLuma sourceVideo -DBparam X start length {-debug}

#benchmarking
stime = Time.new

#Throughout this program, CLIP is the small sequence we want to find, MOVIE is the big sequence we want to search into

#INCLUDES
#
require 'rubygems'
require 'complex'
require 'sqlite3'

#VARIABLES
#
robust = false
debug = false
debug_stats = false
@@param = 5
@@robust_param = ""
sqlite = false
import = false
uprelem = -1.0
hitCounter = 0
l3uniq = false
gcount = 0

(3..ARGV.size-1).each do |arg|
  if ARGV[arg] == "-debug"
    puts("Debug ON")
    debug = true
  elsif ARGV[arg] == "-debug_stats"
    puts("DEBUG STATS ON")
    debug_stats = true
  elsif ARGV[arg] == "-l3uniq"
    puts("L3UNIQ ON")
    l3uniq = true
  elsif ARGV[arg] == "-robust"
    @@robust_param = ARGV[arg+1]
    puts("ROBUSTNESS MODE ON")
    robust = true
  elsif ARGV[arg] == "-DBparam"
    @@param = ARGV[arg+1].to_i
  elsif ARGV[arg] == "-import"
    puts("SQLite import from temp database ON")
    import = true
  elsif ARGV[arg] == "-prelem"
    uprelem = ARGV[arg+1].to_f
    puts("Test mode ON (prelem=#{uprelem})")
  #else
  #  raise RuntimeError, "Illegal command!"
  end
end

#Remaining auxiliary variables
#
sourceVideo = ARGV[0].split('/')[-1]
videoArray = Array.new

#for debug (to use while crawler is still running)
#videoArray.sort!
#videoArray.pop

hitCounter = 0

shall_we_norm = true

##searchSeqArray operations
#
#firstSec = (15*rand(4))
firstSec = ARGV[1].to_i
@@lengthSec = ARGV[2].to_i
#these arrays are already the average of each second or part
searchSeqArrayLumaIni = Array.new
searchSeqArrayChromaUIni = Array.new
searchSeqArrayChromaVIni = Array.new
#total movie arrays
fps = 0.0
ofps = 0.0
lumaArrayAvg = 0
chromaUArrayAvg = 0
chromaVArrayAvg = 0
lumaArrayFrames = Array.new
lumaArraySec = Array.new
chromaUArrayFrames = Array.new
chromaUArraySec = Array.new
chromaVArrayFrames = Array.new
chromaVArraySec = Array.new

#Partition variable for seconds
@@part = 1

savings = 0.0
videoArray.clear

##
#Initialization of databases
if import
	if robust
		db_temp = SQLite3::Database.new( "/home/gsc/test_suj_branch2_central_#{@@robust_param}.db" )
	else
		db_temp = SQLite3::Database.new( "/home/gsc/test_suj_branch3_central.db" )
	end
end

if robust
	db_orig = SQLite3::Database.new( "/home/gsc/test_suj_branch3_central_#{@@param}.db" )
	db = SQLite3::Database.new( "/home/gsc/test_suj_branch2_central_#{@@robust_param}_#{@@param}.db" )
else
	db = SQLite3::Database.new( "/home/gsc/test_suj_branch3_central_#{@@param}.db" )
end

begin
	if import
		#This will make insertion much faster, we don't need this information at every insert
		db.execute("PRAGMA count_changes = OFF")
		db.execute("create table allmovies (allmovieskey INTEGER PRIMARY KEY,name TEXT,fps int)")
		#This will make insertion much faster, we don't need the insertions to be written to HD right away
		db.execute("PRAGMA synchronous = OFF")
		puts("Creating new allmovies table")
	end
rescue
	puts("Allmovies table already exists!")
end

begin
#Initializing hash tables
	if import
		db.execute("create table hashluma (avg_range int, movies TEXT)")
		#db.execute("create table hashcu (avg_range int, movies TEXT)")
		#db.execute("create table hashcv (avg_range int, movies TEXT)")
		print("Creating Hash tables ...")
		STDOUT.flush
		#Inserting into DB all the possible L,Cu,Cv values
		#TODO: we don't need to use all 255 values. The values follow a Standard Distribution centered in x.
		#As the values grow in distance from the center, they are less relevant and the granularity does not need to be as high
		#At the far extremes of this distribution, the Luma values can be segmented into larger slots
		(0..254).each do |n|
			db.execute( "insert into hashluma (avg_range) values (\"#{n}\")")
			#db.execute( "insert into hashcu (avg_range) values (\"#{n}\")")
			#db.execute( "insert into hashcv (avg_range) values (\"#{n}\")")
		end
		puts(" done")
	end
rescue
	puts("Hash tables already exists")
end

#Re-initizlinign videoArray to contain all previously scanned movies by the .c program and sucessfuly inserted in the database
if import 
	db_temp.execute("select * from allmovies").each do |movie|
		videoArray << movie[1]
	end
else
	db.execute("select * from allmovies").each do |movie|
		videoArray << movie[1]
	end
end

##
#CODE

##
#Normalization of _bounded_ vectors
#
#This normalization will take into consideration the length of the movie and the bounding limits
#If the length of the sequence to normalize overflows the size of the array, the normalization 
#will only take into consideration information until the last element of the array
def normBound(array,start,bound,length)
  lower = 1000000
  higher = 0
  temp = Array.new
  
  if bound <= array.size-1
    (start..bound).each do |a|
      lower = array[a] if array[a] < lower
      higher = array[a] if array[a] > higher
    end
  else
    extra = bound-(array.size-1)
    (array.size-1-length*@@part+extra..array.size-1).each do |a|
      lower = array[a] if array[a] < lower
      higher = array[a] if array[a] > higher
    end
  end
  
  aux = 0
  
  if bound <= array.size-1
    (start..bound).each do |a|
      temp[aux] = (array[a] - lower)/(higher-lower) if lower!=higher
	  temp[aux] = array[a]/255 if lower==higher
      aux += 1
    end
  else
    extra = bound-(array.size-1)
    (array.size-length*@@part+extra..array.size-1).each do |a|
      temp[aux] = (array[a] - lower)/(higher-lower) if lower!=higher
	  temp[aux] = array[a]/255 if lower==higher
      aux += 1
    end
  end
  return temp
end

def bound(array,start,bound,length)
  temp = Array.new
  aux = 0
  
  if bound <= array.size-1
    (start..bound).each do |a|
	  temp[aux] = array[a]
      aux += 1
    end
  else
    extra = bound-(array.size-1)
    (array.size-length*@@part+extra..array.size-1).each do |a|
	  temp[aux] = array[a]
      aux += 1
    end
  end
  
  return temp
end

#Normalization of vectors
def norm(array)
  lower = 1000000
  higher = 0

  (0..(array.size-1)).each do |a|
    lower = array[a] if array[a] < lower if array[a] != nil
    higher = array[a] if array[a] > higher if array[a] != nil
  end

  aux = 0
  if higher != 1.0 && lower != 0.0
    (0..(array.size-1)).each do |a|
      array[aux] = (array[a] - lower)/(higher-lower) if array[a] != nil && higher != lower
	  array[aux] = array[a]/255 if array[a] != nil && lower==higher
      #array[aux] = array[a] if array[a] != nil && higher == lower
      aux += 1
    end
  end
  
  return array
end

#Extending our arrays :)
class Array
  #sum (and mean) found on http://snippets.dzone.com/posts/show/2161
  def sum
    inject( nil ) { |sum,x| sum ? sum + x.to_f : x.to_f }
  end
  
  def mean
    sum.to_f / size
  end
  
  #http://en.wikipedia.org/wiki/Mean#Weighted_arithmetic_mean
  def weighted_mean(weights_array)
    raise "Each element of the array must have an accompanying weight.  Array length = #{self.size} versus Weights length = #{weights_array.size}" if weights_array.size != self.size
    w_sum = weights_array.sum
    w_prod = 0
    self.each_index {|i| w_prod += self[i] * weights_array[i].to_f}
    w_prod.to_f / w_sum.to_f
  end
end

#Tanimoto coefficient
class Array 
  def sum
    inject( 0 ) { |sum,x| sum+x }
  end
  def sum_square
    inject( 0 ) { |sum,x| sum+x*x }
  end
  def *(other) # dot_product
    ret = []
    return nil if !other.is_a? Array || size != other.size
    self.each_with_index {|x, i| ret << x * other[i]}
    ret.sum
  end
end

def tanimoto(a, b)
  dot = (a * b)
  den = a.sum_square + b.sum_square - dot
  dot.to_f/den.to_f
end

##
#Cluster information array
#
#This function is a key function in the database storage system. It is responsible for huge savings
#in the space used on the databases.
#Video information has some peculoar characteristics where it will have the same, or near same, amount
#of information in a continuous range of time.
#
#What this function does is group, or cluster, information together according to a user-defined threshold
#When the threshold is surpassed, an index pointer is created and the information is averaged and stored.
#i.e. If from second 12, with value 100, the value decreases to 90 at second 26, with a threshold of 10%
#an index will be created at 26, making a segment from 12 to 26, with an average of 95
#
#Parameters are: 
# -array,it is the original array[]
# -param, it is the threshold
def arrayCluster(array,param)
  arrayCluster = Hash.new()
  c = 0
  procFrames = 0
  temp = 0
  first = array[0].to_f
  
  (0..array.size-2).each do |elem|
	
	if ((first - array[elem].to_f).abs > param.to_f )
      arrayCluster[c] = temp/procFrames if procFrames > 0
	  temp = 0
      procFrames = 0
      c = elem
	  first = array[elem].to_f
    end
    temp += array[elem].to_f
    procFrames += 1
  end
  arrayCluster[c] = temp/procFrames if procFrames > 0
  #add last elem
  arrayCluster[array.size-1] = -1
  
  return arrayCluster
end

#Difference between two arrays
def diff(array1,array2)
  diff = 0.0
  (0..(array1.size-1)).each do |y|
    diff += (array1[y] - array2[y]).abs
  end
  diffAvg = diff / (array1.size-1)
  diffAvg = diff if (array1.size-1) == 0
  return diffAvg
end

#Vector Distance between two arrays
def vectD(array1,array2)
  aux = 0.0
  sqrt= 0.0
  (0..(array1.size-1)).each do |v|
    aux = (array1[v] - array2[v]).abs
    sqrt += aux*aux
  end
  sqrt = Math.sqrt(sqrt) if !sqrt.nan?
  return sqrt
end

#re-order array so that sourceVideo starts first
videoArray.delete(sourceVideo);
videoArray.unshift(sourceVideo);
videoArray.unshift(sourceVideo) if robust

idxDistTimeLClip = Array.new
idxDistLumaClip = Array.new
idxDistTimeLMovie = Array.new
idxDistLumaMovie = Array.new

auxClipArray = Array.new

toSearchL = Hash.new

analyzedVideosCounter = 0
selectedVideosCounter = 0
finalOut = ""

videoArray.each do |video|
	#re-init params
	fps = 0.0
	lumaArrayFrames = Array.new
	lumaArraySec = Array.new
	lumaArraySecCluster = Hash.new
    
	if import  
		##Extract the results
		#
		##
		#When importing from database:
		# -Read from the movie temp DB table, then erase table
		# -If this table isn't empty it's a new movie, which means we will insert it later in a more compact format
		# -If the table exists and is empty, no need to re-import
		##
		begin
			#Get movie information (Luma) from database, each line represents a frame
			db.execute( "select * from '#{video}'" )
			p "Video #{video} is already in database! Skipping analysis ..."
			next
		rescue
			begin
				#Get movie information (Luma) from database, each line represents a frame
				query = db_temp.execute( "select * from '#{video}'" )
			rescue
				raise RuntimeError, "Video #{video} is still not in temporary database! Did you run the videofingerprint.c program beforehand?"
			end
		end
		
		begin
			#Get movie framerate
			fps = db_temp.execute( "select * from allmovies where name = \"#{video}\"")[0][2].to_f
		rescue
			raise RuntimeError, "Video #{video} has not fps info in database! Did you run the videofingerprint.c program beforehand?"
		end
		
		#Read each row (represents a frame) and put the values for L,Cu,Cv into their own array
		rows = query[0..-1].size
		if rows > 0
			(0..rows-1).each do |f|
				lumaArrayFrames[query[f][0].to_i] = query[f][1].to_i
				#chromaUArrayFrames[query[f][0].to_i] = query[f][2].to_i
				#chromaVArrayFrames[query[f][0].to_i] = query[f][3].to_i
			end
		end

		#delete all rows except the table itself
		#db_temp.execute( "delete * from \"#{video}\"" )
		
		raise RuntimeError, "Wrong FPS value for file #{video}" if fps == 0.0
		
		##
		#This will be the huge MOVIE we want to compare to
		##
		begin
			db.execute( "delete from allmovies where name = \"#{video}\"")
		rescue
			puts("Movie #{movie} was already not in the DB. Previous info was _deleted_ ...")
		end
		db.execute( "insert into allmovies (name,fps) values (\"#{video}\",#{(fps*100).to_i})")
		
		##
		#This ID is the movie ID, it will tell us what the unique ID of the movie is in the global allmovies DB
		mid = db.execute( "select * from allmovies where name = \"#{video}\"")[0][0].to_i
		
		c = nil
		##
		# - We use Luma as the characteristic to index to
		# - The values for Cu and Cv are the immediate values for that Luma value
		#
		#We simulate a hashtable in the hash* insertions. For each L,Cu,Cv value we concatenate the movie and the size of the segment
		#that has that luma information.
		#i.e. [140, [20,2][35,1][140,4]] where for luma 140, movie 20 has a segment of 2 seconds, movie 35 has a segment of 1 second, etc
		lumaArraySecCluster = arrayCluster(lumaArrayFrames,@@param)
		#
		#p lumaArraySecCluster.sort
		#p lumaArraySecCluster.keys.sort
		#
		begin
			db.execute( "BEGIN" )
			c = db.execute( "select count(*) from \"#{video}\"" )[0][0].to_i
			raise SQLException if import
		rescue
			keys = lumaArraySecCluster.keys.sort
			begin
				db.execute("drop table \"#{video}\"") if c != nil
				db.execute2("create table \"#{video}\" (s_end FLOAT, luma INTEGER)")
				(0..keys.size-2).each do |x| 
					#Convert values to 2-byte integers [0-255].00 * 100 <= 25599 which is lower than 65535 (thanks Christian!)
					avgLuma = (lumaArraySecCluster[keys[x]]*100).to_i
					#avgChromaU = (chromaUArrayFrames[keys[x]]*100).to_i
					#avgChromaV = (chromaVArrayFrames[keys[x]]*100).to_i
					#insert in DB
					db.execute( "insert into \"#{video}\" (s_end,luma) values (#{keys[x]/fps},#{avgLuma})")
					#p "db.execute( \"insert into \"#{video}\" (s_end,luma,chromau,chromav) values (#{keys[x]},#{avgLuma},#{avgChromaU},#{avgChromaV})\")"
					#append to "hashtables"
					prev = db.execute( "select * from hashluma where avg_range = \"#{(avgLuma/100.0).round}\"" )
					if !prev.empty?
						prev = prev[0][1]
					else
						prev = "".to_s if prev.empty?
					end
					#Luis' idea
					db.execute( "update hashluma set movies = \"#{prev.to_s+mid.to_s+":"+(((keys[x]/fps)*100).round/100.0).to_s+"-"+(((keys[x+1]/fps)*100).round/100.0).to_s+","}\" where avg_range = \"#{(avgLuma/100.0).round}\"" ) if prev.to_s.split(',').index(mid.to_s) == nil
					#db.execute( "update hashluma set movies = \"#{prev.to_s+mid.to_s+":"+(keys[x+1]-keys[x]).to_s+","}\" where avg_range = \"#{(avgLuma/100.0).round}\"" ) if prev.to_s.split(',').index(mid.to_s) == nil
				end
			rescue
				p "Problem inserting data into movie own table or hashtable!"
			end
			#insert last element
			db.execute( "insert into \"#{video}\" (s_end,luma) values (#{keys[keys.size-1]/fps},-1)")
		end
		db.execute("END")

		# We are only importing, no need to waste time on searching
		##
		print("Finished importing #{video}, now skipping to next video ...\n") if import
		next if import
	end
  
	##
	#Now we will read the information from the database
	if robust && searchSeqArrayLumaIni.size == 0 && sourceVideo == video
		fps = db_orig.execute( "select * from allmovies where name = \"#{video}\"")[0][2].to_f
		ofps = fps/100
	else
		fps = db.execute( "select * from allmovies where name = \"#{video}\"")[0][2].to_f
	end
	#req = db.execute( "select * from allmovies where name = \"#{video}\"")
	#next if req[0] == nil
	#fps = req[0][2].to_f
	raise SQLException if fps < 1 || fps == nil
	fps /= 100
	
	##
	#Now we will read the information from the database
    # 
	#Array reconstruction:
	# -Here the information, after getting collected in the previous step, is reconstructed
	# -We start from the clustered information in the database and recreate FPS/part information
	#
	#We clear the arrays for now because they have been used in the past, before inserting into the DB
    lumaArraySec.clear
    #chromaUArraySec.clear
    #chromaVArraySec.clear
    lumaArraySecCluster.clear
    #chromaUArraySecCluster.clear
    #chromaVArraySecCluster.clear
	
	##
	#This ID is the movie ID, it will tell us what the unique ID of the movie is in the global allmovies DB
	if robust && searchSeqArrayLumaIni.size == 0 && sourceVideo == video
		mid = db_orig.execute( "select * from allmovies where name = \"#{video}\"")[0][0].to_i
	else
		mid = db.execute( "select * from allmovies where name = \"#{video}\"")[0][0].to_i
	end
    
	##
	# - Luma has then most accurate values
	# - The values for Cu and Cv were the immediate values for that Luma value, and are hence less accurate

    #query will be a bi-dimensional array with [time] x [luma,chromau,chromav]
    begin
		if robust && searchSeqArrayLumaIni.size == 0
			query = db_orig.execute( "select * from \"#{video}\"" )
		else
			query = db.execute( "select * from \"#{video}\"" )
		end
    rescue
		raise RuntimeError, "Video is not in database! Did you run the -import flag beforehand?"
	end
	#Each row is one segment of time from the information clustering
	rows = query[0..-1].size
	(0..rows-2).each do |r|
		lumaArraySecCluster[((query[r][0].to_f)*100).to_i/100.0] = query[r][1].to_f/100.0
		#chromaUArraySecCluster[((query[r][0].to_f)*100).to_i/100.0] = query[r][2].to_f/100.0
		#chromaVArraySecCluster[((query[r][0].to_f)*100).to_i/100.0] = query[r][3].to_f/100.0
		#Here we expand the time segment into a full segment
		#i.e. if we have row with a range of [5..15]
		#we unfold it into 10 rows
		(((query[r][0].to_f*fps).round)..(query[r+1][0].to_f*fps).round-1).each do |l|
			lumaArrayFrames[l] = (query[r][1].to_i)/100.0
			#chromaUArrayFrames[l] = (query[r][2].to_i)/100.0
			#chromaVArrayFrames[l] = (query[r][3].to_i)/100.0
		end
	end
	#The last element needs special treatment, we just need a pointer of the time the finishes
	#That is out last element. No further information is stored here
	lumaArraySecCluster[((query[rows-1][0].to_f)*100).to_i/100.0] = (query[rows-2][1].to_i)/100.0
	#chromaUArraySecCluster[((query[rows-1][0].to_f)*100).to_i/100.0] = (query[rows-2][2].to_i)/100.0
	#chromaVArraySecCluster[((query[rows-1][0].to_f)*100).to_i/100.0] = (query[rows-2][3].to_i)/100.0
	
	if debug
		puts "Info for movie #{video} off the DB:"
		puts "Frames (lumaArrayFrames.uniq) :"
		p lumaArrayFrames.uniq
		puts "Clustered (lumaArraySecCluster.sort):"
		p lumaArraySecCluster.sort
	end
  
	print("Video has a length of #{(lumaArrayFrames.size-1)/fps} seconds and each second is divided in #{@@part} parts\n") if debug
  
	####CLIP WE WANT TO LOOK FOR (PATTERN TO SEARCH)
	#This is what we want to find when searching other movies
	#
	##
	#If the movie has the same name as the input movie provided in ARGV[0]
	#We consider this to be the source video we want to look for and extract the clip from that video
	#
	#After the movie was processed by the information clustering mechanisms and the information is in *ArraySec[] arrays,
	#we can start comparing with our database. For that we populate the searchSeqArray*Ini[] arrays with the CLIP we want
	#to look for
	#
	#If the time sequence we want to look for is bigger than the movie or surpasses the total time of the movie, we cut
	#the search time up to the end of the movie.
	#i.e. If we want to search for seconds [5..25] in a movie with total length of [0..20], the new searched sequence will
	#be [5..20]. A warning is issued when this issue arises.
	#
	#Excuse the @@lengthSec/@@part maths ;) Will get improved/clarified later on
	if sourceVideo == video && searchSeqArrayLumaIni.size == 0
		aux = 0
		print("Using as source video:#{video}\n")
		#If we're between limits (clip is within whole movie time)
		if (lumaArrayFrames.size-1)/fps >= firstSec+@@lengthSec
			((firstSec*fps).round..((firstSec*fps).round+((@@lengthSec*fps)-1).round)).each do |x|
				#print("Populating position #{aux} with #{lumaArrayFrames[x]} [#{firstSec}-#{firstSec+@@lengthSec-1}]\n") if debug
				searchSeqArrayLumaIni[aux] = lumaArrayFrames[x]
				#searchSeqArrayChromaUIni[aux] = chromaUArrayFrames[x]
				#searchSeqArrayChromaVIni[aux] = chromaVArrayFrames[x]
				
				aux += 1
			end
		else
			puts("WARNING! The video you're looking at is too short for the chosen time slot search!\nLooking for [#{firstSec}~#{firstSec+@@lengthSec}] in #{video} movie which has a size of [0~#{lumaArraySec.size-1}].") if (lumaArraySec.size-1)/@@part < firstSec+@@lengthSec
			print("Video has a length of #{(lumaArraySec.size-1)/fps} seconds and each second is divided in #{@@part} parts\n") if debug
			raise RuntimeError, "Video #{video} has no such segment [#{firstSec}~#{firstSec+@@lengthSec}] or is too small (#{(lumaArrayFrames.size-1)/fps-firstSec})" if ((lumaArrayFrames.size-1)/fps-firstSec < 3)
			puts("Using #{video}:[#{firstSec}~#{(lumaArrayFrames.size-1)/fps}] instead (#{(lumaArrayFrames.size-1)/fps-firstSec} secs).")
			@@lengthSec = ((lumaArrayFrames.size-1)/fps)-firstSec
			((firstSec*fps).round..((firstSec*fps).round+((@@lengthSec*fps)-1).round)).each do |x|
				#print("Populating position #{aux} with #{lumaArrayFrames[x]} [#{firstSec}-#{firstSec+@@lengthSec-1}]\n") if debug
				searchSeqArrayLumaIni[aux] = lumaArrayFrames[x]
				#searchSeqArrayChromaUIni[aux] = chromaUArrayFrames[x]
				#searchSeqArrayChromaVIni[aux] = chromaVArrayFrames[x]
			
				aux += 1
			end
		end

		##
		#These arrays will help calculate the CLIP information after being processed by the arrayCluster() function
		tempArray = lumaArraySecCluster.sort
		#test = arrayCluster(searchSeqArrayLumaIni,@@param)
		counter = 0
		(0..lumaArraySecCluster.size-1).each do |n|
			#TO FIX, this firstSec+0.5 crap makes no sense
			auxClipArray << tempArray[n-1] if tempArray[n][0] > firstSec && tempArray[n][0] <= firstSec+@@lengthSec && counter == 0
			auxClipArray << tempArray[n] if tempArray[n][0] >= firstSec && tempArray[n][0] <= firstSec+@@lengthSec
			#Fixes case where intevrals are too long (0s to 30s) and we want to search for second 10~25
			auxClipArray << tempArray[n] if auxClipArray.size == 1 && tempArray[n][0] > firstSec+@@lengthSec
			if tempArray[n+1] != nil && tempArray[n+1][0] >= firstSec+@@lengthSec && tempArray[n][0] <= firstSec
				auxClipArray << tempArray[n]
			end
			counter += 1 if tempArray[n][0] >= firstSec && tempArray[n][0] <= firstSec+@@lengthSec
		end
		
		#To summarize:
		#test has the CLIP cluster info, as a hash
		#searchSeqArrayLumaIni has the CLIP frames
		
		##
		#These arrays will sort the distances between IDXs of L,Cu and Cv for the CLIP
		(0..auxClipArray.size-2).each do |d|
			idxDistTimeLClip << ((auxClipArray[d+1][0].to_f-auxClipArray[d][0].to_f)*100).round/100.0
			idxDistLumaClip << ((auxClipArray[d+1][1].to_f-auxClipArray[d][1].to_f)*100).round/100.0
		end
		
		##
		#Take care of the special last case, where not real information is stored, only time
		#idxDistTimeLClip << auxClipArray[auxClipArray.size-1][0]-auxClipArray[auxClipArray.size-2][0]
		#idxDistTimeCuClip << auxClipArray1[auxClipArray1.size-1][0]-auxClipArray1[auxClipArray1.size-2][0]
		#idxDistTimeCvClip << auxClipArray2[auxClipArray2.size-1][0]-auxClipArray2[auxClipArray2.size-2][0]
		#idxDistLumaClip << (auxClipArray[auxClipArray.size-1][1]-auxClipArray[auxClipArray.size-2][1]).abs
		#idxDistCuClip << (auxClipArray1[auxClipArray1.size-1][1]-auxClipArray1[auxClipArray1.size-2][1]).abs
		#idxDistCvClip << (auxClipArray2[auxClipArray2.size-1][1]-auxClipArray2[auxClipArray2.size-2][1]).abs
		#idxDistLumaClip = norm(idxDistLumaClip)
		
		#Normalize the CLIP array
		#searchSeqArrayLumaIni = norm(searchSeqArrayLumaIni)
		#searchSeqArrayChromaUIni = norm(searchSeqArrayChromaUIni)
		#searchSeqArrayChromaVIni = norm(searchSeqArrayChromaVIni)
		
		if debug
			puts "#### start CLIP info"
			puts "#"
			puts "Post-clustered frames (searchSeqArrayLumaIni.uniq):"
			p searchSeqArrayLumaIni.uniq
			puts "Cluster info (auxClipArray):"
			p auxClipArray
			puts "Delta of time (in frames) (idxDistTimeLClip):\n#{idxDistTimeLClip.join(" ")}"
			puts "Delta of Luma () idxDistLumaClip:\n#{idxDistLumaClip.join(" ")}"
			puts "#"
			puts "#### end CLIP info"
		end
	end
	####
	
	#if robust && sourceVideo == video && searchSeqArrayLumaIni.size != 0
	#	p "Redoing search with distorted copy of #{video}"
	#	redo
	#end
	
	##
	#Now we search the big MOVIE to find our sequence

	print("#{video}: Seaching video:#{video}\n")  if debug_stats || debug
	puts("-------------------------------------------------------------") if debug

	realFrame = -1
	auxDiffLuma = Array.new
	auxSqrtLuma = Array.new
	taniLuma = Array.new

	###
	## Calculate the distance between IDXs and L,Cu,Cv for MOVIE
	###
	auxArray = Array.new
	auxArray = lumaArraySecCluster.sort
	#auxArray = arrayCluster(lumaArrayFrames,@@param)
	idxDistTimeLMovie.clear
	idxDistLumaMovie.clear

	##
	#The idxDist*[Time|[Luma|Cu|Cv]]Clip[] arrays will be storing the distance information of the CLIP we want to search for
	(0..auxArray.size-2).each do |d|
		idxDistTimeLMovie << ((auxArray[d+1][0].to_f-auxArray[d][0].to_f)*100).round/100.0
		idxDistLumaMovie << ((auxArray[d+1][1].to_f-auxArray[d][1].to_f)*100).round/100.0
	end

	#p idxDistTimeLMovie
	#p idxDistLumaMovie

	##
	#Take care of the special last case, where no real information but time is stored
	#idxDistTimeLMovie << (auxArray[auxArray.size-1][0]-auxArray[auxArray.size-2][0])*fps
	#idxDistTimeCuMovie << (auxArray1[auxArray1.size-1][0]-auxArray1[auxArray1.size-2][0])*fps
	#idxDistTimeCvMovie << (auxArray2[auxArray2.size-1][0]-auxArray2[auxArray2.size-2][0])*fps
	#idxDistLumaMovie << (auxArray[auxArray.size-1][1]-auxArray[auxArray.size-2][1]).abs
	#idxDistCuMovie << (auxArray1[auxArray1.size-1][1]-auxArray1[auxArray1.size-2][1]).abs
	#idxDistCvMovie << (auxArray2[auxArray2.size-1][1]-auxArray2[auxArray2.size-2][1]).abs
	
	if debug
		puts "#### start VIDEO info"
		puts "#"
		puts "Post-clustered frames (auxArray):"
		p auxArray
		puts "Delta of time (in frames) (idxDistTimeLMovie):\n#{idxDistTimeLMovie.join(" ")}"
		puts "Delta of Luma (idxDistLumaMovie):\n#{idxDistLumaMovie.join(" ")}"
		puts "#"
		puts "#### end VIDEO info"
	end
	
	##
	# HIERARCHICAL SEARCH
	#
	# There are 3 hierarchical levels in this algorithm:
	#  - Level 1 will select movies that have segments with the same Luma
	#  - Level 2 will select movies that have similar distances between indexes
	#  - Level 3 will use the distance vector and tanimoto algorithms for a thorough search

	##
	#Level 1: 
	# - Select movies that have a segment with the same Luma value
	#
	#Thresholds in this section:
	# - NONE
	#
	b_val1 = false
	b_val2 = false
	found_idx = Array.new
	#
	b_array = Array.new
	b_thresh = uprelem
	#
	aaux = Array.new
	
	if toSearchL.empty?
		#for every idx in the CLIP, compare its Luma values with hash
		arrayCluster(searchSeqArrayLumaIni,@@param).sort.each do |avg|
			next if avg[1] < 0
			#add movies with similar luma as the index to toSearchL[]
			qArray = Array.new
			#TODO play with this -1 and +1 value
			qArray = db.execute( "select * from hashluma where avg_range between #{((avg[1].to_f).round)-1} and #{((avg[1].to_f).round)+1}" )
			#qArray = db.execute( "select * from hashluma where avg_range = #{((avg[1].to_f).round)}" )
			(0..qArray.size-1).each do |e|
				next if qArray[e][1] == nil
				qArray[e][1].to_s.split(',').sort.uniq.each do |tuple|
					aaux = tuple.to_s.split(':')
					toSearchL[aaux[0].to_i] = Array.new if toSearchL.has_key?(aaux[0].to_i) == false
					toSearchL[aaux[0].to_i] << aaux[1] if toSearchL[aaux[0].to_i].include?(aaux[1]) == false
				end
			end
		end
		#p toSearchL.sort
	end
	
	#If the MOVIE has no segments related to the CLIP, skip it!
	if toSearchL[mid] == nil
		puts "#{video}: [L0] Skipping MOVIE #{video}" if debug_stats
		next
	end
	
	##
	#Measure the amount of seconds the MOVIE has with the same luma as the CLIP
	#
	sum = 0
	tarray = Array.new
	#p "#{video} #{toSearchL[mid].sort.join(" ")}"
	#toSearchL[mid] => [10.3 15.77 0.75 1.88 15.89 16.56]
	#toSearchL[mid].join(" ") => 10.3-15.77 0.75-1.88 15.89-16.56 ...
	toSearchL[mid].each do |segment|
		sarray = segment.split("-")
		if tarray.index(sarray[0].to_f) == nil
			tarray << sarray[0].to_f
		else
			tarray.delete(sarray[0].to_f)
		end
		
		if tarray.index(sarray[1].to_f) == nil
			tarray << sarray[1].to_f
		else
			tarray.delete(sarray[1].to_f)
		end
		
		sum += sarray[1].to_f-sarray[0].to_f
	end
	
	#If that amount correlates (is contiguous) this MOVIE to the segment we're looking for, make it a possible HIT
	#sumdiff = 0.0
	#if sum > @@lengthSec*0.4
	diff = 0
	c = 1
	seqIdx = c-1
	contSecs = 0
	while c < tarray.size-1 do
		diff = tarray.sort[c+1]-tarray.sort[c]
		if diff > 10
			#sumdiff += diff
			seqIdx = c-1
		end
		if diff < 1
			sum += diff
		end
		c = c + 2
		contSecs = tarray.sort[c]-tarray.sort[seqIdx]
		seqIdx = seqIdx+2 if tarray.sort[c]-tarray.sort[seqIdx] > @@lengthSec
		#p("Diff between tarray.sort[#{c}] and tarray.sort[#{c}] = #{diff}; Secs of contiguous info[#{tarray.sort[seqIdx]}~#{tarray.sort[c]}]:#{contSecs}; Sum = #{sum}") if debug
		break if contSecs >= @@lengthSec
	end
	#end
	
	#p tarray.sort #if contSecs >= @@lengthSec*0.4
	#p "#{video} has a sum of #{sum} and contSecs of #{contSecs} and a diff of #{diff}" #if contSecs >= @@lengthSec*0.4 if debug
	
	b_val1 = true if (sum+diff) >= @@lengthSec*0.4
	
	if b_val1 == false
		puts "#{video}: [L1] Skipping MOVIE #{video}" if debug_stats || debug
		next	
	end
  
	##
	#Level 2:
	#Thresholds in this section:
	# - b_thresh
	#
	#for qcif anf 5fps:
	b_thresh = 0.1
	#b_thresh = 0.1
	#for qcif anf 5fps:
	b_thresh_L = @@param
	#b_thresh_L = 1.0
	found_idx.clear
	if b_val1 == true
		selectedVideosCounter += 1

		#find CLIP IDXs in MOVIE IDXs
		#p idxDistTimeLMovie
		#p idxDistLumaMovie
		#p "=="
		#p idxDistTimeLClip
		#p idxDistLumaClip
		(0..idxDistTimeLMovie.size-1).each do |x|
			count = 0
			countL = 0
			countG = 0
		
			##
			# Rant mode ON
			#
			#Here is a tricky part of the algorithm. When looking for different movies, timings and lumas might slightly vary.
			#However, we cannot directly access an array on those slightly different indexes (we cannot search by "does an element 3.04 +/- 0.5 exist?")
			#Also, sometimes the modified movies have more or less indexes (i.e. an original interval of [3.05 20][4.1 40] appears as [3.05 20][3.6 30][4.1 40])
			#This also throws off the original algorithm of searching item by item movie[1] vs clip[1], movie[2] vs clip[2], etc
			#So the fix (although slow) and taking into account the CLIP array is small, is to compare all the elements inside, then we can use the +/- 0.5 lookups
			#Bonus: the arrays are already time sorted, so we're only searching within segments of X secs maximum
			#
			# Rant mode OFF
			##
=begin
			if x-1 <= idxDistTimeLMovie.size-idxDistTimeLClip.size
				b_array = idxDistLumaMovie[x..x+idxDistTimeLClip.size-1]
				(0..idxDistTimeLClip.size-1).each do |y|
					next if b_array[y] == nil
					if b_thresh > 0.0 || b_thresh_L > 0.0
						#for each CLIP element
							#while MOVIE time between X seconds of the CLIP element's time
						count += 1 if idxDistTimeLMovie[x+y] >= idxDistTimeLClip[y]-b_thresh && idxDistTimeLMovie[x+y] <= idxDistTimeLClip[y]+b_thresh
						countL += 1 if b_array[y] >= idxDistLumaClip[y]-b_thresh_L && b_array[y] <= idxDistLumaClip[y]+b_thresh_L
					else
						count += 1 if idxDistTimeLMovie[x+y] == idxDistTimeLClip[y]
						countL += 1 if b_array[y] == idxDistLumaClip[y]
					end
				end
			end
=end		
#=begin			
			#p auxClipArray
			if x-1 <= idxDistTimeLMovie.size-idxDistTimeLClip.size
				#for each MOVIE segment of the size of the CLIP segment we are looking for
				#TO FIX: this will only give an estimate, if we have more indexes in the MOVIE, this will cut the last ones
				b_array = auxArray[x..x+idxDistTimeLClip.size-1]
				
				count = 0
				countL = 0
				countG = 0
				
				auxClipArray.each do |clipElem|
					#next if b_array[clipElem] == nil
					
					if b_thresh > 0.0 || b_thresh_L > 0.0
						#search for elements between |clipElem|+/-b_thresh in b_array
						b_array.each do |movieElem|
							#Time and luma
							if clipElem[0].to_f-b_thresh <= movieElem[0].to_f && clipElem[0].to_f+b_thresh >= movieElem[0].to_f && clipElem[1].to_f-b_thresh_L <= movieElem[1].to_f && clipElem[1].to_f+b_thresh_L >= movieElem[1].to_f
								#p "#{x} T: #{clipElem} ~= #{movieElem}"
								countG += 1 
							end
						end
					else
						b_array.each do |movieElem|
							#Time
							count += 1 if movieElem[0] == clipElem[0]
							#Luma
							countL += 1 if movieElem[1] == clipElem[1]						
						end
					end
				
				end
			end
#=end
			
			#p "L #{video}: idx=#{x} sec:#{auxArray[x][0]} Count=#{count}/#{idxDistTimeLClip.size} CountL=#{countL}/#{idxDistLumaClip.size}"
			
			#p "L #{video}: idx=#{x} sec:#{auxArray[x][0]} CountG=#{countG}/#{idxDistLumaClip.size}"

			if countG >= idxDistLumaClip.size
				puts "#{video}: L: idx=#{x} sec:#{auxArray[x][0]} CountG=#{countG}/#{idxDistLumaClip.size}"
				found_idx << x
				b_val2 = true
			end
			
=begin			
			if countL > 0 && count > 0
			
				#p "L #{video}: idx=#{x} sec:#{auxArray[x][0]} Count=#{count}/#{idxDistTimeLClip.size} CountL=#{countL}/#{idxDistLumaClip.size}"
				#p "#{video}: idx=#{x} Count=#{count}/#{idxDistTimeLClip.size-1} CountL=#{countL}/#{idxDistTimeLClip.size-1}"
			
				if idxDistTimeLClip.size <= 5
					if count >= idxDistTimeLClip.size-1 && countL >= idxDistLumaClip.size-1
						p "#{video}: idx=#{x} sec:#{auxArray[x][0]} Count=#{count}/#{idxDistTimeLClip.size} CountL=#{countL}/#{idxDistLumaClip.size}" if debug
						found_idx << x
						b_val2 = true
						next				
					end				
				elsif idxDistTimeLClip.size < 10 && idxDistTimeLClip.size > 5
					#Used to be: idxDistTimeLClip.size-4 && countL >= idxDistLumaClip.size-3
					if count >= idxDistTimeLClip.size-4 && countL >= idxDistLumaClip.size-4
						p "#{video}: idx=#{x} sec:#{auxArray[x][0]} Count=#{count}/#{idxDistTimeLClip.size} CountL=#{countL}/#{idxDistLumaClip.size}" if debug
						found_idx << x
						b_val2 = true
						next				
					end
				else
					#changing these 0.6 and 0.9 ratios might improve speed *to tune*
					if count >= (idxDistTimeLClip.size)*0.6 && countL >= (idxDistLumaClip.size)*0.2
						p "#{video}: idx=#{x} sec:#{auxArray[x][0]} Count=#{count}/#{idxDistTimeLClip.size} CountL=#{countL}/#{idxDistLumaClip.size}" if debug
						found_idx << x
						b_val2 = true
						next
					end
				end
			end
=end
		end
		
	end

	##
	#If the clip we're looking for does not have the same time intervals, for the luma we're looking for, as the clip we want to find, discard it
	if b_val2 == false
		puts "#{video}: [L2] Skipping MOVIE #{video}" if debug_stats || debug
		next
	end

	p "#{video} passed to phase 2 with initial idx of #{found_idx.join(",")}" if debug

	analyzedVideosCounter += 1
	#puts("Searching #{toSearchCv.size} of 210 movies")
	
	##
	#Level 2.5 (Dimensional Tales):
	#
	#The idea behind this level is to quickly compare all the information gathered, laying it in 4 dimensions.
	#Dimension 1 will be the Luma value before an index
	#Dimension 2 will be the Luma value after an index
	#Dimension 3 will be the duration of the previous Luma step
	#Dimension 4 will be the sequential order, in time, of the indexes
	#TODO: include magnitude of the jump (dimension 2.5 or 3.5?)

	##
	#Level 3:
	# - Tanimoto and distance vector
	#
	#Fast Search will search at every index of the big MOVIE for our CLIP. If the current index difference is higher than a set of thresholds 
	#defined as vscore and tscore, the algorithm will search for the next index. By skipping to the next index instead of analyzing
	#every second we gain a considerable amount of time and can keep reasonable results.
	#p lumaArraySecCluster.keys.sort
	(0..(lumaArraySecCluster.keys.size - 1)).each do |idx|
		#TO FIX: we're limiting the search until the last element hit the end of the clip
		#We should still search, but with smaller, bounded, arrays
		next if !found_idx.include?(idx)
		break if (lumaArraySecCluster.keys.sort[idx].to_f*fps).round+@@lengthSec*fps.to_i > (lumaArrayFrames.size-1)
		#p found_idx
		
		p "reached idx #{idx}" if debug
		
		mArray = Array.new	
		
		#between auxArray[idx][0] and auxArray[idx][0]+@@lengthSec
			#for each elem from auxArray[idx][1] to auxArray[idx+1][1]
				#add it to mArray at the original fps
		
		n=idx
		while ((auxArray[n][0].to_f) <= ((auxArray[idx][0].to_f)+@@lengthSec))
			break if idxDistTimeLMovie[n] == nil
			if robust
				(idxDistTimeLMovie[n]*ofps).round.times { mArray << auxArray[n][1].to_f}
			else
				(idxDistTimeLMovie[n]*fps).round.times { mArray << auxArray[n][1].to_f}
			end
			n+=1
		end
		
		#number of frames to discard initially
		#this way we can search from second firstSec and ignore the initial junk
		#a [9.32..12.0] segment will become [10.0..12.0]
		if robust
			initDiscard = (firstSec-auxArray[idx][0].to_f)*ofps.ceil
		else
			initDiscard = (firstSec-auxArray[idx][0].to_f)*fps.ceil
		end
		mArray = mArray[initDiscard..-1] if initDiscard > 0
		
		#Skip to next index if it clearly is not a match
		next if mArray == nil

		## 
		#We can use .uniq for smaller vectors, but difference is minimal
		#We can still fully compare in the next step, if we use .uniq here
		##
		 
		#The first two cases should be the normal happenings; however, let's just 
		#be sure nothing bad happens
		if l3uniq
			if ( searchSeqArrayLumaIni.uniq.size < mArray.uniq.size )
				bound = searchSeqArrayLumaIni.uniq.size-1
				tscore = tanimoto(searchSeqArrayLumaIni.uniq, mArray.uniq[0..bound])
				
				#p "1"
				
				p searchSeqArrayLumaIni.uniq if debug
				p mArray[0..bound].uniq if debug
			elsif ( searchSeqArrayLumaIni.uniq.size == mArray.uniq.size )
				tscore = tanimoto(searchSeqArrayLumaIni.uniq, mArray.uniq)
				
				#p "2"
				
				p searchSeqArrayLumaIni.uniq if debug
				p mArray.uniq if debug
			else #( searchSeqArrayLumaIni.size > mArray.size )
				bound = mArray.uniq.size-1
				tscore = tanimoto(searchSeqArrayLumaIni.uniq[0..bound], mArray.uniq)
				
				p searchSeqArrayLumaIni.uniq#[0..bound] if debug
				p mArray.uniq #if debug
			end
		else
			if ( searchSeqArrayLumaIni.size < mArray.size )
				bound = searchSeqArrayLumaIni.size-1
				tscore = tanimoto(searchSeqArrayLumaIni, mArray[0..bound])
				
				p searchSeqArrayLumaIni if debug
				p mArray[0..bound] if debug
			elsif ( searchSeqArrayLumaIni.size == mArray.size )
				tscore = tanimoto(searchSeqArrayLumaIni, mArray)
				
				p searchSeqArrayLumaIni if debug
				p mArray if debug
			else #( searchSeqArrayLumaIni.size > mArray.size )
				bound = mArray.size-1
				tscore = tanimoto(searchSeqArrayLumaIni[0..bound], mArray)
				
				p searchSeqArrayLumaIni[0..bound] if debug
				p mArray if debug
			end
		end
		
		puts("#{video}: tanimoto for idx=#{idx} #{lumaArraySecCluster.keys.sort[idx]}(#{lumaArraySecCluster.keys.sort[idx]*fps.round})~#{lumaArraySecCluster.keys.sort[idx]+@@lengthSec}(#{(lumaArraySecCluster.keys.sort[idx]+@@lengthSec)*fps.round}): #{tscore}") if debug || debug_stats

		#Compare with tanimoto
		#if low value, skip to next index
		#for qcif anf 5fps:
		if tscore < 0.85
		#if tscore < 0.97
			puts "#{video}: [L3] Skipping segment #{lumaArraySecCluster.keys.sort[idx]}(#{lumaArraySecCluster.keys.sort[idx]*fps.round})~#{lumaArraySecCluster.keys.sort[idx]+@@lengthSec}(#{(lumaArraySecCluster.keys.sort[idx]+@@lengthSec)*fps.round}) of MOVIE #{video}" if debug_stats || debug
			next
		end
		
		#vscore = vectD(searchSeqArrayLumaIni, mArray)
		#p "vector distance for #{lumaArraySecCluster.keys.sort[idx]}~#{lumaArraySecCluster.keys.sort[idx]+@@lengthSec}: #{vscore}"
		
		#next if vscore > 400
		line = ""
		old_f = -1
		old_t = -1
		old_v = 9999999999
		
		#p searchSeqArrayLumaIni.size
		#p searchSeqArrayLumaIni
		#p searchSeqArrayLumaIni.uniq.inject([]){|r, i| r << { :value => i, :count => searchSeqArrayLumaIni.select{ |b| b == i }.size } }
		#p mArray.size
		#p mArray
		#p mArray.uniq.inject([]){|r, i| r << { :value => i, :count => mArray.select{ |b| b == i }.size } }
		
		l3counter = -1
		
		### Use index or begin of index + time?
		##
		#
		puts("#{video}: Further analysing segment #{(lumaArraySecCluster.keys.sort[idx].to_f*fps).round}..#{((lumaArraySecCluster.keys.sort[idx].to_f+(@@lengthSec/2))*fps).round}") if debug || debug_stats
		((lumaArraySecCluster.keys.sort[idx].to_f*fps).round..((lumaArraySecCluster.keys.sort[idx].to_f+(@@lengthSec/2))*fps).round).each do |x|
		##p "[#{video}] Further analysing segment #{(lumaArraySecCluster.keys.sort[idx].to_f*fps).round}..#{(lumaArraySecCluster.keys.sort[idx+1].to_f*fps).round}" if debug || debug_stats
		##((lumaArraySecCluster.keys.sort[idx].to_f*fps).round..(lumaArraySecCluster.keys.sort[idx+1].to_f*fps).round).each do |x|
			
			#if we hit the next index, skip to it
			#break if x >= lumaArraySecCluster.keys.sort[idx+1].to_f*fps
			
			l3counter+=1
			
			diffLuma = 0.0
			similarLumaAvg = 0.0
			diffLumaAvg = Array.new
			distLuma = Array.new
      
			partNumb = x%@@part
			realFrame += 1 if partNumb == 0
      
			#tempArrayLuma = Array.new
      
			##
			#If we exceed the end of the array do as if we were within the last bounds of the movie
			#BUT discard the last exceeding number of elements of the array
			#bound = x+(@@lengthSec*@@part*fps).to_i-1
			#if shall_we_norm
			#	tempArrayLuma = normBound(lumaArrayFrames,x,bound,@@lengthSec)
			#else
			#	tempArrayLuma = bound(lumaArrayFrames,x,bound,@@lengthSec)
			#end
			
			#tempArrayLuma = lumaArrayFrames[x..x+(@@lengthSec*@@part*fps).to_i]
			tempArrayLuma = mArray
	  
			##
			#When reaching the end of the array, we had a condition where the values outside of the array would be compared
			#Ex: Searching for 10 second blocks in a 60 second movie, would give us a search between [55-65]. 
			#Also, we don't want to compare only 1 second (too many false positives). 5 seconds is the lowest piece we search.
			if ( lumaArrayFrames.size-x < @@lengthSec*@@part*fps )
				bound = lumaArrayFrames.size-x-1
				searchSeqArrayLuma = searchSeqArrayLumaIni[0..bound]
			else
				##
				#Only look for second IDX of CLIP and before last IDX
				searchSeqArrayLuma = searchSeqArrayLumaIni#[auxClipArray[1][0]..auxClipArray[-2][0]-1]
			end
			
			##
			#ALGORITHMS

			if searchSeqArrayLuma[0..[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min].size == tempArrayLuma[l3counter..l3counter+[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min].size
				a1 = searchSeqArrayLuma[0..[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min]
				a2 = tempArrayLuma[l3counter..l3counter+[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min]
			elsif searchSeqArrayLuma[0..[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min].size > tempArrayLuma[l3counter..l3counter+[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min].size
				a1 = searchSeqArrayLuma[0..tempArrayLuma[l3counter..l3counter+[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min].size-1]
				a2 = tempArrayLuma[l3counter..l3counter+[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min]
			else #if searchSeqArrayLuma[0..[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min].size < tempArrayLuma[l3counter..l3counter+[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min].size
				a1 = searchSeqArrayLuma[0..[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min]
				a2 = tempArrayLuma[l3counter..l3counter+searchSeqArrayLuma[0..[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min]]
			end
			
			break if a2.size == 0 || a1.size == 0 || a1.size != a2.size
			
			##
			#Tanimoto
			taniLuma[x] = tanimoto(a1, a2)
    
			##
			#Difference between CLIP and MOVIE
			#auxDiffLuma[x] = diff(a1, a2)
    
			##
			#Distance between vectors
			auxSqrtLuma[x] = vectD(a1, a2)
			
			#0.995 2 60
			#if false
			#for qcif anf 5fps:
			#0.9 doesntmatter 340

			if auxSqrtLuma[x] < 340 && taniLuma[x] > 0.9 #&& auxDiffLuma[x] < 2 
				if auxSqrtLuma[x] < old_v || taniLuma[x] > old_t
					if taniLuma[x] > old_t || auxSqrtLuma[x] < old_v
						#line = sprintf("%s: %d LDiff:%2.5f LVectD:%2.5f TaniL:%2.5f\n", video, x, auxDiffLuma[x], auxSqrtLuma[x], taniLuma[x])
						line = sprintf("%s [%d]: %d LVectD:%2.5f TaniL:%2.5f\n", video, gcount, x, auxSqrtLuma[x], taniLuma[x])
						#line = sprintf("%s: %d LVectD:%2.5f\n", video, x, auxSqrtLuma[x])
						#printf("###%s: %d LVectD:%2.5f\n", video, x, auxSqrtLuma[x])
						old_t = taniLuma[x]
						old_f = x
						old_v = auxSqrtLuma[x]
					end
				end	
			#elsif debug_stats
			end
			#printf("###%s: %d LVectD:%2.5f TaniL:%2.5f\n", video, x, auxSqrtLuma[x], taniLuma[x]) if debug
		end
		
		if line != ""
			hitCounter += 1
			print line
		end
	
	end
	gcount += 1

end
db.close()

puts("No hits were found! :(") if hitCounter == 0 && !import
puts("")
puts(finalOut)

print("Database clustering saved an average of ","%5.2f" % (savings/(videoArray.size-1)),"% on Luma", "\n") if import
print("Hits found: #{hitCounter}\n")
print("Selected videos: #{selectedVideosCounter} Analyzed videos: #{analyzedVideosCounter}\n")
print("Test run-time for #{videoArray.size} movies was ","%5.2f" % (Time.new-stime), " seconds\n")