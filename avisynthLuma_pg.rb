##
# Usage
##
# avisynthLuma sourceVideo start length {-DBparam X} {-debug}
##

##
# Throughout this program, CLIP is the small sequence we want to find, MOVIE is the big sequence we want to search in
##

#benchmarking
stime = Time.new

##
# INCLUDES
##
require 'rubygems'
require 'complex'
require 'postgres'

##
# VARIABLES
##
robust = false
debug = false
debug_stats = false
@@param = 6
@@robust_param = ""
sqlite = false
uprelem = -1.0
hitCounter = 0

(3..ARGV.size-1).each do |arg|
  if ARGV[arg] == "-debug"
    puts("Debug ON")
    debug = true
  elsif ARGV[arg] == "-debug_stats"
    puts("DEBUG STATS ON")
    debug_stats = true
  elsif ARGV[arg] == "-robust"
    @@robust_param = ARGV[arg+1]
    puts("ROBUSTNESS MODE ON")
    robust = true
  elsif ARGV[arg] == "-DBparam"
    @@param = ARGV[arg+1].to_i
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
hitCounter = 0
shall_we_norm = true
firstSec = ARGV[1].to_i
@@lengthSec = ARGV[2].to_i
#Partition variable for seconds
@@part = 1
savings = 0.0
analyzedVideosCounter = 0
selectedVideosCounter = 0
finalOut = ""

###
##
# Initialization of databases
##
###
if robust
	db = PGconn.connect("192.168.4.135", 5432, "", "", "videofingerprint", "skillup", "skillupjapan" )
	db_orig = PGconn.connect("192.168.4.135", 5432, "", "", "videofingerprint", "skillup", "skillupjapan" )
else
	db = PGconn.connect("192.168.4.135", 5432, "", "", "videofingerprint", "skillup", "skillupjapan" )
end

###
##
# Auxiliary functions
##
###

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
# -array, it is the original array[]
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

####
###
##
# Code
##
###
####

##
# Creating the smaller CLIP we want to search for
##

##
# Init params
idxDistTimeLClip = Array.new
idxDistLumaClip = Array.new
idxDistTimeLMovie = Array.new
idxDistLumaMovie = Array.new
toSearchL = Hash.new

clip_fps = 0.0
clip_mid = -1
clip_lumaArrayFrames = Array.new
clip_lumaArraySec = Array.new
clip_lumaArraySecCluster = Hash.new

##
# Get the CLIP fps
if robust
	clip_fps = db_orig.exec( "select fps from allmovies where name = \'#{sourceVideo}\'")[0][0].to_f
else
	clip_fps = db.exec( "select fps from allmovies where name = \'#{sourceVideo}\'")[0][0].to_f
end
raise SQLException if clip_fps < 1 || clip_fps == nil
clip_fps /= 100

##
# This clip_mid is the movie ID, it will tell us what the unique ID of the movie is in the global allmovies DB
if robust
	clip_mid = db_orig.exec( "select allmovieskey from allmovies where name = \'#{sourceVideo}\'")[0][0].to_i
else
	clip_mid = db.exec( "select allmovieskey from allmovies where name = \'#{sourceVideo}\'")[0][0].to_i
end

##
# Luma is the most accurate

query = nil
#query will be a bi-dimensional array with [time] x [luma,chromau,chromav]
begin
	if robust 
		query = db_orig.exec( "select unnest(video_fp) from allmovies where name='#{sourceVideo}'" )
	else
		query = db.exec( "select unnest(video_fp) from allmovies where name='#{sourceVideo}'" )
	end
rescue
	raise RuntimeError, "Video is not in database! Did you run the -import flag beforehand?"
end
#Each row is one segment of time from the information clustering
r = 0
query.each do |e|
	if r.odd?
	    r += 1
	    next
	end
	clip_lumaArraySecCluster[((query[r][0].to_f)*100).to_i/100.0] = query[r+1][0].to_i/100.0
	#Here we expand the time segment into a full segment
	#i.e. if we have row with a range of [5..15]
	#we unfold it into 10 rows
	break if query[r+2] == nil
	(((query[r][0].to_f*clip_fps).round)..(query[r+2][0].to_f*clip_fps).round-1).each do |l|
		clip_lumaArrayFrames[l] = (query[r+1][0].to_i)/100.0
	end
	r+=1
end
#The last element needs special treatment, we just need something that informs us it's over
#No time information is stored here
clip_lumaArraySecCluster[((query[r][0].to_f)*100).to_i/100.0] = (query[r+1][0].to_i)/100.0
	
if debug
	puts "Info for movie #{sourceVideo} off the DB:"
	puts "Frames (lumaArrayFrames.uniq) :"
	p clip_lumaArrayFrames.uniq
	puts "Time (lumaArraySec.uniq) :"
	p clip_lumaArraySec.uniq
	puts "Clustered (lumaArraySecCluster.sort):"
	p clip_lumaArraySecCluster.sort
end

##
# This is what we want to find when searching other movies
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

searchSeqArrayLumaIni = Array.new
searchSeqArrayTimeIni = Array.new

##
#These arrays will help calculate the CLIP information after being processed by the arrayCluster() function
auxClipArray = Array.new
tempArray = clip_lumaArraySecCluster.sort
counter = 0
(0..clip_lumaArraySecCluster.size-1).each do |n|
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


#Excuse the @@lengthSec/@@part maths ;) Will get improved/clarified later on
aux = 0
print("Using as source video:#{sourceVideo}\n")
#If we're between limits (clip is within whole movie time)
if (clip_lumaArrayFrames.size-1)/clip_fps >= firstSec+@@lengthSec
	((firstSec*clip_fps).round..((firstSec*clip_fps).round+((@@lengthSec*clip_fps)-1).round)).each do |x|
		#print("Populating position #{aux} with #{clip_lumaArrayFrames[x]} [#{firstSec}-#{firstSec+@@lengthSec-1}]\n") if debug
		searchSeqArrayLumaIni[aux] = clip_lumaArrayFrames[x]
		searchSeqArrayTimeIni[aux] = auxClipArray.rassoc(clip_lumaArrayFrames[x])[0]
		aux += 1
	end
else
	puts("WARNING! The video you're looking at is too short for the chosen time slot search!\nLooking for [#{firstSec}~#{firstSec+@@lengthSec}] in #{sourceVideo} movie which has a size of [0~#{clip_lumaArraySec.size-1}].") if (clip_lumaArraySec.size-1)/@@part < firstSec+@@lengthSec
	print("Video has a length of #{(clip_lumaArraySec.size-1)/clip_fps} seconds and each second is divided in #{@@part} parts\n") if debug
	raise RuntimeError, "Video #{sourceVideo} has no such segment [#{firstSec}~#{firstSec+@@lengthSec}] or is too small (#{(lumaArrayFrames.size-1)/clip_fps-firstSec})" if ((clip_lumaArrayFrames.size-1)/clip_fps-firstSec < 3)
	puts("Using #{video}:[#{firstSec}~#{(clip_lumaArrayFrames.size-1)/clip_fps}] instead (#{(clip_lumaArrayFrames.size-1)/clip_fps-firstSec} secs).")
	@@lengthSec = ((lumaArrayFrames.size-1)/clip_fps)-firstSec
	((firstSec*clip_fps).round..((firstSec*clip_fps).round+((@@lengthSec*clip_fps)-1).round)).each do |x|
		#print("Populating position #{aux} with #{clip_lumaArrayFrames[x]} [#{firstSec}-#{firstSec+@@lengthSec-1}]\n") if debug
		searchSeqArrayLumaIni[aux] = clip_lumaArrayFrames[x]
		searchSeqArrayTimeIni[aux] = auxClipArray.rassoc(clip_lumaArrayFrames[x])[0]
		aux += 1
	end
end
	
##
#These arrays will sort the distances between IDXs of L,Cu and Cv for the CLIP
(0..auxClipArray.size-2).each do |d|
	idxDistTimeLClip << ((auxClipArray[d+1][0].to_f-auxClipArray[d][0].to_f)*100).round/100.0
	idxDistLumaClip << ((auxClipArray[d+1][1].to_f-auxClipArray[d][1].to_f)*100).round/100.0
end

##	
#Normalize the CLIP array

#searchSeqArrayLumaIni = norm(searchSeqArrayLumaIni)
clipArrayCluster = arrayCluster(searchSeqArrayLumaIni,@@param).sort
#p clipArrayCluster
##
# Populate the toSearchL hash
#
# Expected result:
#
# luma1 | luma2 | movies |                               time                                
#-------+-------+--------+-------------------------------------------------------------------
#    20 |    26 | 2,2    | 1948.429226,1951.389270,1984.789771,1992.789891
#    20 |    32 | 2      | 2039.470592,2046.710700
#    23 |    32 | 1,2,2  | 68.326549,68.409976,274.484117,278.764181,1930.148952,1930.588958
#
(0..clipArrayCluster.size-1).each do |s|
	next if clipArrayCluster[s][1] < 0
	#add movies with similar luma as the index to toSearchL[]
	qArray = db.exec( "SELECT m1.avg_range_1 as luma1, m1.avg_range_2 as luma2, array_to_string(movies[1:90000][1], ',') as movies, array_to_string(movies[1:90000][2:3], ',') as time FROM (SELECT movies[2:9000],avg_range_1,avg_range_2 from hashluma where avg_range_1>=#{((clipArrayCluster[s][1].to_f).floor)-1} and avg_range_1<=#{((clipArrayCluster[s][1].to_f).floor+1)} and avg_range_2>=#{((clipArrayCluster[s+1][1].to_f).floor)-1} and avg_range_2<=#{((clipArrayCluster[s+1][1].to_f).floor+1)} and movies[2:9000]!='{}') as M1 order by avg_range_1,avg_range_2" )
	qArray.each do |e|
		next if e[0] == nil
		timings = e[3].to_s.split(',')
		movies = e[2].to_s.split(',')
		(0..movies.size-1).each do |m|
			next if m.odd?
			toSearchL[movies[m].to_i] = Array.new if toSearchL.has_key?(movies[m].to_i) == false
			toSearchL[movies[m].to_i] << timings[m]
			toSearchL[movies[m].to_i] << timings[m+1]
		end
	end
	break if clipArrayCluster[s+2] == nil
end
#p toSearchL.sort


if debug
	puts "#### start CLIP info"
	puts "#"
	puts "Post-clustered frames (searchSeqArrayLumaIni.uniq):"
	p searchSeqArrayLumaIni.uniq
	puts "Post-clustered time (clip_searchSeqArrayTimeIni.uniq):"
	p searchSeqArrayTimeIni.uniq
	puts "Cluster info (auxClipArray):"
	p auxClipArray
	puts "Delta of time (in frames) (idxDistTimeLClip):\n#{idxDistTimeLClip.join(" ")}"
	puts "Delta of Luma () idxDistLumaClip:\n#{idxDistLumaClip.join(" ")}"
	puts "#"
	puts "#### end CLIP info"
end

####	
###
##
# Now we will search for the CLIP in all the other movies
##
###
####

#Initializing videoArray to contain all previously scanned movies by the .c program, inserted in the database
videoArray = Array.new
db.exec("select * from allmovies").each { |movie| videoArray << movie[1] }

#re-order array so that sourceVideo starts first
videoArray.delete(sourceVideo);
videoArray.unshift(sourceVideo);
videoArray.unshift(sourceVideo) if robust

videoArray.each do |video|

	print("Searching video:#{video}\n")  if debug_stats || debug
	puts("-------------------------------------------------------------") if debug

	fps = 0.0
	mid = 0
	
	####
	###
	##
	# HIERARCHICAL SEARCH
	#
	# There are 3 hierarchical levels in this algorithm:
	#  - Level 0 & 1 will select movies that have segments with the same Luma
	#  - Level 2 will select movies that have similar distances between indexes
	#  - Level 3 will use the distance vector and tanimoto algorithms for a thorough search
	##
	###
	####

	###
	##
	#Level 0 : Discard movies that have no relation with our CLIP
	##
	###
	#ID is the movie ID, it will tell us what the unique ID of the movie is in the global allmovies DB
	#FPS is the movie frames per second, multiplied by 100
	if robust
		req = db_orig.exec("select fps,allmovieskey from allmovies where name = '#{video}'")
		fps = req[0][0].to_f
		mid = req[0][1].to_i
	else
		req = db.exec("select fps,allmovieskey from allmovies where name = '#{video}'")
		fps = req[0][0].to_f
		mid = req[0][1].to_i
	end
	raise SQLException if fps < 1 || fps == nil
	fps /= 100

	#If the MOVIE has no segments related to the CLIP, skip it!
	if toSearchL[mid] == nil
		puts "[L0.1] Skipping MOVIE #{video}" if debug_stats
		next
	end

	## If the number of segments is 80% different, this is not our movie
	#
	if toSearchL[mid].size <= toSearchL[clip_mid].size*0.8 || toSearchL[mid].size >= toSearchL[clip_mid].size*1.2
		puts "[L0.2] Skipping MOVIE #{video}" if debug_stats
		next
	end

	###
	##
	#Level 1 : Select related MOVIEs that have a similar amount of segments with similar Luma values of CLIP
	##
	###
	#Thresholds in this section:
	# - TODO (Play with the +/- 1 value in the DB requests)
	# - TODO (Play with the 80% different number of segments)
	# - TODO (Play with the 60% different amount of time)
	#
	b_val1 = false
	b_val2 = false
	found_idx = Array.new
	b_array = Array.new
	qArray = nil

	##
	#Measure the amount of seconds the MOVIE has with the same luma as the CLIP
	sum = 0
	tarray = Array.new
	(0..toSearchL[mid].size-1).each do |s|
		next if s%2 != 0
		if tarray.index(toSearchL[mid][s].to_f) == nil
			tarray << toSearchL[mid][s].to_f
		else
			tarray.delete(toSearchL[mid][s].to_f)
		end
		
		if tarray.index(toSearchL[mid][s+1].to_f) == nil
			tarray << toSearchL[mid][s+1].to_f
		else
			tarray.delete(toSearchL[mid][s+1].to_f)
		end
		
		sum += toSearchL[mid][s+1].to_f-toSearchL[mid][s].to_f
	end

	#If that amount correlates (is contiguous) this MOVIE to the CLIP we're looking for, make it a possible HIT
	diff = 0
	c = 1
	seqIdx = c-1
	contSecs = 0
	while c < tarray.size-1 do
		diff = tarray.sort[c+1]-tarray.sort[c]
		if diff > 10
			seqIdx = c-1
		end
		if diff < 1
			sum += diff
		end
		c = c + 2
		contSecs = tarray.sort[c]-tarray.sort[seqIdx]
		seqIdx = seqIdx+2 if tarray.sort[c]-tarray.sort[seqIdx] > @@lengthSec
		#p("Diff between tarray.sort[#{c}] and tarray.sort[#{c}] = #{diff}; Secs of contiguous info[#{tarray.sort[seqIdx]}~#{tarray.sort[c]}]:#{contSecs}; Sum = #{sum}")
		break if contSecs >= @@lengthSec
	end
	
	b_val1 = true if (sum+diff) >= @@lengthSec*0.4 || (sum+diff) <= @@lengthSec*1.6
	
	if b_val1 == false
		puts "[L1] Skipping MOVIE #{video}" if debug_stats || debug
		next	
	end
  
	##
	#Array reconstruction:
	# - We start from the clustered information in the database and recreate FPS/part information
        #query will be a bi-dimensional array with [time] x [luma]
	lumaArrayFrames = Array.new
	lumaArraySec = Array.new
	lumaArraySecCluster = Hash.new
        begin
		if robust
			query = db_orig.exec( "select unnest(video_fp) from allmovies where name='#{video}'" )
		else
			query = db.exec( "select unnest(video_fp) from allmovies where name='#{video}'" )
		end
        rescue
		raise RuntimeError, "Video is not in database! Did you run the -import flag beforehand?"
	end
	#Each row is one segment of time from the information clustering
	r = 0
	query.each do |e|
		if r.odd?
		    r += 1
		    next
		end
		lumaArraySecCluster[((query[r][0].to_f)*100).to_i/100.0] = query[r+1][0].to_i/100.0
		#Here we expand the time segment into a full segment
		#i.e. if we have row with a range of [5..15]
		#we unfold it into 10 rows
		break if query[r+2] == nil
		(((query[r][0].to_f*fps).round)..(query[r+2][0].to_f*fps).round-1).each do |l|
			lumaArrayFrames[l] = (query[r+1][0].to_i)/100.0
		end
		r+=1
	end
	#The last element needs special treatment, we just need a pointer of the time the finishes
	#That is out last element. No further information is stored here
	lumaArraySecCluster[((query[r][0].to_f)*100).to_i/100.0] = (query[r+1][0].to_i)/100.0
	
	if debug
		puts "Info for movie #{video} off the DB:"
		puts "Frames (lumaArrayFrames.uniq) :"
		p lumaArrayFrames.uniq
		puts "Time (lumaArraySec.uniq) :"
		p lumaArraySec.uniq
		puts "Clustered (lumaArraySecCluster.sort):"
		p lumaArraySecCluster.sort
	end
  
	print("Video has a length of #{(lumaArrayFrames.size-1)/fps} seconds and each second is divided in #{@@part} parts\n") if debug
  	
	## Calculate the distance between IDXs and Luma for MOVIE
	#
	auxArray = Array.new
	auxArray = lumaArraySecCluster.sort
	#auxArray = arrayCluster(lumaArrayFrames,@@param)
	idxDistTimeLMovie.clear
	idxDistLumaMovie.clear

	##
	#The idxDist*{Time,Luma}Clip[] arrays will be storing the distance information of the CLIP we want to search for
	(0..auxArray.size-2).each do |d|
		idxDistTimeLMovie << ((auxArray[d+1][0].to_f-auxArray[d][0].to_f)*100).round/100.0
		idxDistLumaMovie << ((auxArray[d+1][1].to_f-auxArray[d][1].to_f)*100).round/100.0
	end

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

	###
	##
	#Level 2:
	##
	###
	#Thresholds in this section:
	# - b_thresh
	#
	#for qcif and 5fps:
	#b_thresh = 0.2
	b_thresh = 0.1
	#for qcif and 5fps:
	#b_thresh_L = 2.0
	b_thresh_L = 1.0
	realFrame = -1
	auxDiffLuma = Array.new
	auxDiffTime = Array.new
	auxSqrtLuma = Array.new
	auxSqrtTime = Array.new
	taniLuma = Array.new
	taniTime = Array.new
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
		
			if x-1 <= idxDistTimeLMovie.size-idxDistTimeLClip.size
				b_array = idxDistLumaMovie[x..x+idxDistTimeLClip.size-1]
				(0..idxDistTimeLClip.size-1).each do |y|
					next if b_array[y] == nil
					if b_thresh > 0.0 || b_thresh_L > 0.0
						count += 1 if idxDistTimeLMovie[x+y] >= idxDistTimeLClip[y]-b_thresh && idxDistTimeLMovie[x+y] <= idxDistTimeLClip[y]+b_thresh
						countL += 1 if b_array[y] >= idxDistLumaClip[y]-b_thresh_L && b_array[y] <= idxDistLumaClip[y]+b_thresh_L
					else
						count += 1 if idxDistTimeLMovie[x+y] == idxDistTimeLClip[y]
						countL += 1 if b_array[y] == idxDistLumaClip[y]
					end
				end
			end
			
			#p "L #{video}: idx=#{x} sec:#{auxArray[x][0]} Count=#{count}/#{idxDistTimeLClip.size} CountL=#{countL}/#{idxDistLumaClip.size}"

			if count > 0 && countL > 0
			
				#p "L #{video}: idx=#{x} sec:#{auxArray[x][0]} Count=#{count}/#{idxDistTimeLClip.size} CountL=#{countL}/#{idxDistLumaClip.size}"
				#p "#{video}: idx=#{x} Count=#{count}/#{idxDistTimeLClip.size-1} CountL=#{countL}/#{idxDistTimeLClip.size-1}"
			
				if idxDistTimeLClip.size <= 4
					if count >= idxDistTimeLClip.size-1 && countL >= idxDistLumaClip.size-1
						p "#{video}: idx=#{x} sec:#{auxArray[x][0]} Count=#{count}/#{idxDistTimeLClip.size} CountL=#{countL}/#{idxDistLumaClip.size}" if debug
						found_idx << x
						b_val2 = true
						next				
					end				
				elsif idxDistTimeLClip.size < 10 && idxDistTimeLClip.size > 4
					#Used to be: idxDistTimeLClip.size-4 && countL >= idxDistLumaClip.size-3
					if count >= idxDistTimeLClip.size-4 && countL >= idxDistLumaClip.size-4
						p "#{video}: idx=#{x} sec:#{auxArray[x][0]} Count=#{count}/#{idxDistTimeLClip.size} CountL=#{countL}/#{idxDistLumaClip.size}" if debug
						found_idx << x
						b_val2 = true
						next				
					end
				else
					#changing these 0.7 and 0.4 ratios might improve speed *to tune*
					if count >= (idxDistTimeLClip.size)*0.7 && countL >= (idxDistLumaClip.size)*0.4
						p "#{video}: idx=#{x} sec:#{auxArray[x][0]} Count=#{count}/#{idxDistTimeLClip.size} CountL=#{countL}/#{idxDistLumaClip.size}" if debug
						found_idx << x
						b_val2 = true
						next
					end
				end
			end
		end
		
	end

	##
	#If the clip we're looking for does not have the same time intervals, for the luma we're looking for, as the clip we want to find, discard it
	if b_val2 == false
		puts "[L2] Skipping MOVIE #{video}" if debug_stats || debug
		next
	end

	p "#{video} passed to phase 2 with initial idx of #{found_idx.join(",")}" if debug

	analyzedVideosCounter += 1
	#puts("Searching #{toSearchCv.size} of 210 movies")

	##
	#Level 3:
	# - Tanimoto and distance vector
	#
	#Fast Search will search at every found_idx of the big MOVIE for our CLIP. If the current index difference is higher than a set of thresholds 
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
		
		mArrayL = Array.new
		mArrayT = Array.new
		
		#between auxArray[idx][0] and auxArray[idx][0]+@@lengthSec
			#for each elem from auxArray[idx][1] to auxArray[idx+1][1]
				#add it to mArrayL at the original fps
		
		n=idx
		while ((auxArray[n][0].to_f) <= ((auxArray[idx][0].to_f)+@@lengthSec))
			if robust
				(idxDistTimeLMovie[n]*clip_fps).round.times { mArrayL << auxArray[n][1].to_f}
				(idxDistTimeLMovie[n]*clip_fps).round.times { mArrayT << auxArray[n][0].to_f}
			else
				(idxDistTimeLMovie[n]*fps).round.times { mArrayL << auxArray[n][1].to_f}
				(idxDistTimeLMovie[n]*fps).round.times { mArrayT << auxArray[n][0].to_f}
			end
			n+=1
		end

		## 
		#We can use .uniq for smaller vectors, but difference is minimal
		#We can still fully compare in the next step, if we use .uniq here
		##
		
		#The first two cases should be the normal happenings; however, let's just 
		#be sure nothing bad happens
		if ( searchSeqArrayLumaIni.size < mArrayL.size )
			bound = searchSeqArrayLumaIni.size-1
			tscoreL = tanimoto(searchSeqArrayLumaIni, mArrayL[0..bound])
				
			p "l1--" if debug
			p searchSeqArrayLumaIni if debug
			p "-" if debug
			p mArrayL[0..bound] if debug
			p "l1--" if debug
		elsif ( searchSeqArrayLumaIni.size == mArrayL.size )
			tscoreL = tanimoto(searchSeqArrayLumaIni, mArrayL)
			
			p "l2--" if debug
			p searchSeqArrayLumaIni if debug
			p "-" if debug
			p mArrayL if debug
			p "l2--" if debug
		else #( searchSeqArrayLumaIni.size > mArrayL.size )
			bound = mArrayL.size-1
			tscoreL = tanimoto(searchSeqArrayLumaIni[0..bound], mArrayL)
			
			p "l3--" if debug
			p searchSeqArrayLumaIni[0..bound] if debug
			p "-" if debug
			p mArrayL if debug
			p "l3--" if debug
		end
		
		if ( searchSeqArrayTimeIni.size < mArrayT.size )
			bound = searchSeqArrayTimeIni.size-1
			tscoreT = tanimoto(searchSeqArrayTimeIni, mArrayT[0..bound])
			
			p "t1--" if debug
			p searchSeqArrayTimeIni if debug
			p "-" if debug
			p mArrayT[0..bound] if debug
			p "t1--" if debug
		elsif ( searchSeqArrayTimeIni.size == mArrayT.size )
			tscoreT = tanimoto(searchSeqArrayTimeIni, mArrayT)
			
			p "t2--" if debug
			p searchSeqArrayTimeIni if debug
			p "-" if debug
			p mArrayT if debug
			p "t2--" if debug
		else #( searchSeqArrayTimeIni.size > mArrayT.size )
			bound = mArrayL.size-1
			tscoreT = tanimoto(searchSeqArrayTimeIni[0..bound], mArrayT)
			
			p "--" if debug
			p searchSeqArrayTimeIni[0..bound] if debug
			p "-" if debug
			p mArrayT if debug
			p "--" if debug
		end
		
		p "tanimoto for idx=#{idx} #{lumaArraySecCluster.keys.sort[idx]}(#{lumaArraySecCluster.keys.sort[idx]*fps.round})~#{lumaArraySecCluster.keys.sort[idx]+@@lengthSec}(#{(lumaArraySecCluster.keys.sort[idx]+@@lengthSec)*fps.round}): Luma:#{tscoreL} Time:#{tscoreT} " if debug || debug_stats

		#Compare with tanimoto
		#if low value, skip to next index
		#for qcif anf 5fps:
		if tscoreL < 0.85 && tscoreT < 0.85
		#if tscoreL < 0.97
			puts "[L3] Skipping segment #{lumaArraySecCluster.keys.sort[idx]}(#{lumaArraySecCluster.keys.sort[idx]*fps.round})~#{lumaArraySecCluster.keys.sort[idx]+@@lengthSec}(#{(lumaArraySecCluster.keys.sort[idx]+@@lengthSec)*fps.round}) of MOVIE #{video}" if debug_stats || debug
			next
		end

		p "tanimoto for idx=#{idx} #{lumaArraySecCluster.keys.sort[idx]}(#{lumaArraySecCluster.keys.sort[idx]*fps.round})~#{lumaArraySecCluster.keys.sort[idx]+@@lengthSec}(#{(lumaArraySecCluster.keys.sort[idx]+@@lengthSec)*fps.round}): Luma:#{tscoreL} Time:#{tscoreT} " 

		p "[L3] #{video} Passed tanimoto"

		#vscore = vectD(searchSeqArrayLumaIni, mArrayL)
		#p "vector distance for #{lumaArraySecCluster.keys.sort[idx]}~#{lumaArraySecCluster.keys.sort[idx]+@@lengthSec}: #{vscore}"
		
		#next if vscore > 400
		lineL = ""
		lineT = ""
		oldl_f = -1
		oldl_t = -1
		oldl_v = 9999999999
		oldt_f = -1
		oldt_t = -1
		oldt_v = 9999999999
		
		#p searchSeqArrayLumaIni.size
		#p searchSeqArrayLumaIni
		#p searchSeqArrayLumaIni.uniq.inject([]){|r, i| r << { :value => i, :count => searchSeqArrayLumaIni.select{ |b| b == i }.size } }
		#p mArrayL.size
		#p mArrayL
		#p mArrayL.uniq.inject([]){|r, i| r << { :value => i, :count => mArrayL.select{ |b| b == i }.size } }
		
		l3counter = -1
		
		### Use index or begin of index + time?
		##
		#
		p "[#{video}] Further analysing segment #{(lumaArraySecCluster.keys.sort[idx].to_f*fps).round}..#{((lumaArraySecCluster.keys.sort[idx].to_f+(@@lengthSec/2))*fps).round}" if debug || debug_stats
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
			tempArrayLuma = mArrayL
			tempArrayTime = mArrayT
	  
			##
			#When reaching the end of the array, we had a condition where the values outside of the array would be compared
			#Ex: Searching for 10 second blocks in a 60 second movie, would give us a search between [55-65]. 
			#Also, we don't want to compare only 1 second (too many false positives). 5 seconds is the lowest piece we search.
			if ( lumaArrayFrames.size-x < @@lengthSec*@@part*fps )
				bound = lumaArrayFrames.size-x-1
				searchSeqArrayLuma = searchSeqArrayLumaIni[0..bound]
				searchSeqArrayTime = searchSeqArrayTimeIni[0..bound]
			else
				##
				#Only look for second IDX of CLIP and before last IDX
				searchSeqArrayLuma = searchSeqArrayLumaIni#[auxClipArray[1][0]..auxClipArray[-2][0]-1]
				searchSeqArrayTime = searchSeqArrayTimeIni#[auxClipArray[1][0]..auxClipArray[-2][0]-1]
			end
			
			##
			#ALGORITHMS

			if searchSeqArrayLuma[0..[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min].size == tempArrayLuma[l3counter..l3counter+[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min].size
				#p "1"
				a1L = searchSeqArrayLuma[0..[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min]
				a2L = tempArrayLuma[l3counter..l3counter+[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min]
			elsif searchSeqArrayLuma[0..[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min].size > tempArrayLuma[l3counter..l3counter+[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min].size
				#p "2"
				a1L = searchSeqArrayLuma[0..tempArrayLuma[l3counter..l3counter+[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min].size-1]
				a2L = tempArrayLuma[l3counter..l3counter+[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min]
			else #if searchSeqArrayLuma[0..[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min].size < tempArrayLuma[l3counter..l3counter+[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min].size
				#p "3"
				a1L = searchSeqArrayLuma[0..[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min]
				a2L = tempArrayLuma[l3counter..l3counter+searchSeqArrayLuma[0..[searchSeqArrayLuma.size-1,tempArrayLuma.size-1].min]]
			end
			
			if searchSeqArrayTime[0..[searchSeqArrayTime.size-1,tempArrayTime.size-1].min].size == tempArrayTime[l3counter..l3counter+[searchSeqArrayTime.size-1,tempArrayTime.size-1].min].size
				#p "1"
				a1T = searchSeqArrayTime[0..[searchSeqArrayTime.size-1,tempArrayTime.size-1].min]
				a2T = tempArrayTime[l3counter..l3counter+[searchSeqArrayTime.size-1,tempArrayTime.size-1].min]
			elsif searchSeqArrayTime[0..[searchSeqArrayTime.size-1,tempArrayTime.size-1].min].size > tempArrayTime[l3counter..l3counter+[searchSeqArrayTime.size-1,tempArrayTime.size-1].min].size
				#p "2"
				a1T = searchSeqArrayTime[0..tempArrayTime[l3counter..l3counter+[searchSeqArrayTime.size-1,tempArrayTime.size-1].min].size-1]
				a2T = tempArrayTime[l3counter..l3counter+[searchSeqArrayTime.size-1,tempArrayTime.size-1].min]
			else #if searchSeqArrayTime[0..[searchSeqArrayTime.size-1,tempArrayTime.size-1].min].size < tempArrayTime[l3counter..l3counter+[searchSeqArrayTime.size-1,tempArrayTime.size-1].min].size
				#p "3"
				a1T = searchSeqArrayTime[0..[searchSeqArrayTime.size-1,tempArrayTime.size-1].min]
				a2T = tempArrayTime[l3counter..l3counter+searchSeqArrayTime[0..[searchSeqArrayTime.size-1,tempArrayTime.size-1].min]]
			end
			
			##
			#Tanimoto
			#taniLuma[x] = tanimoto(a1L, a2L)
			#taniTime[x] = tanimoto(a1T, a2T)
    
			##
			#Difference between CLIP and MOVIE
			#auxDiffLuma[x] = diff(a1L, a2L)
			#auxDiffLuma[x] = diff(a1T, a2T)
    
			##
			#Distance between vectors
			auxSqrtLuma[x] = vectD(a1L, a2L)
			auxSqrtTime[x] = vectD(a1T, a2T)

			#0.995 2 60
			#if false
			#for qcif anf 5fps:
			#if auxSqrtLuma[x] < 340
			if auxSqrtLuma[x] < 60 && auxSqrtTime[x] < 60
			#if auxSqrtLuma[x] < 60 && taniLuma[x] > 0.995 && auxDiffLuma[x] < 2 
				#if taniLuma[x] > old_t
				if auxSqrtLuma[x] < oldl_v
					#line = sprintf("%s: %d LDiff:%2.5f LVectD:%2.5f TaniL:%2.5f\n", video, x, auxDiffLuma[x], auxSqrtLuma[x], taniLuma[x])
					lineL = sprintf("%s: %d LVectD:%2.5f\n", video, x, auxSqrtLuma[x])
					#printf("###%s: %d LVectD:%2.5f\n", video, x, auxSqrtLuma[x])
					oldl_t = taniLuma[x]
					oldl_f = x
					oldl_v = auxSqrtLuma[x]
				end
				if auxSqrtTime[x] < oldt_v
					#line = sprintf("%s: %d TDiff:%2.5f TVectD:%2.5f TaniT:%2.5f\n", video, x, auxDiffTime[x], auxSqrtTime[x], taniTime[x])
					lineT = sprintf("%s: %d TVectD:%2.5f\n", video, x, auxSqrtTime[x])
					#printf("###%s: %d LVectD:%2.5f\n", video, x, auxSqrtLuma[x])
					oldt_t = taniTime[x]
					oldt_f = x
					oldt_v = auxSqrtTime[x]
				end	
			#elsif debug_stats
			#	printf("###%s: %d LVectD:%2.5f\n", video, x, auxSqrtLuma[x])
			end
		end
		
		if lineT != "" || lineL != ""
			hitCounter += 1
			print lineL
			print lineT
		end
	
	end

end
db.close()

puts("No hits were found! :(") if hitCounter == 0
puts("")
puts(finalOut)

print("Hits found: #{hitCounter}\n")
print("Selected videos: #{selectedVideosCounter} Analyzed videos: #{analyzedVideosCounter}\n")
print("Test run-time for #{videoArray.size} movies was ","%5.2f" % (Time.new-stime), " seconds\n")
