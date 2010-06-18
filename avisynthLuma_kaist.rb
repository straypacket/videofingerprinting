#Usage
#avisynthLuma sourceVideo start {-debug}

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
gui = false
debug = false
sqlite = false
dist = ""
mac = false
l3fact = 0.3
hitCounter = 0
thresh = 300
min = false

(2..ARGV.size-1).each do |arg|
  if ARGV[arg] == "-debug"
    #puts("Debug ON")
    debug = true
  elsif ARGV[arg] == "-mac"
    mac = true
  elsif ARGV[arg] == "-min"
    min = true
  elsif ARGV[arg] == "-dist"
    dist = ARGV[arg+1].to_s
    #puts("Dist mode ON (dist=#{dist})")
  elsif ARGV[arg] == "-l3fact"
    l3fact = ARGV[arg+1].to_f
    #puts("Dist mode ON (l3fact=#{l3fact})")
  #else
  #  raise RuntimeError, "Illegal command!"
  elsif ARGV[arg] == "-thresh"
    thresh = ARGV[arg+1].to_f
    #puts("Thresh manual mode ON (thresh=#{thresh})")
  end
end

#Remaining auxiliary variables
#
sourceVideo = ARGV[0]
videoArray = Array.new

#for debug (to use while crawler is still running)
#videoArray.sort!
#videoArray.pop

##searchSeqArray operations
#
#firstSec = (15*rand(4))
firstSec = ARGV[1].to_i
@@lengthSec = ARGV[2].to_i
#total movie arrays
fps = 0.0
ofps = 0.0

K = 100

savings = 0.0
videoArray.clear

if mac
	path = "/Users/gsc"
else
	path = "/home/gsc"
end

##
#Initialization of databases
begin
	if dist.empty?
		db = SQLite3::Database.new( "#{path}/test_cgo_modelling.db" )
	else
		orig_db = SQLite3::Database.new( "#{path}/test_cgo_modelling.db" )
		db = SQLite3::Database.new( "#{path}/test_cgo_modelling_#{dist}.db" )
	end
rescue
	raise SQLException
end
#
db.execute("select * from allmovies").each do |movie|
	videoArray << movie[1]
end

##
#CODE

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
    aux = (array1[v].to_f - array2[v].to_f).abs
    sqrt += aux*aux
  end
  sqrt = Math.sqrt(sqrt) if !sqrt.nan?
  return sqrt
end

#re-order array so that sourceVideo starts first
videoArray.delete(sourceVideo);
videoArray.unshift(sourceVideo);

analyzedVideosCounter = 0
selectedVideosCounter = 0

#re-init params
#Thresh for lookups with no distortions:
#thresh = 8; T = 0.0004
#
#thresh = 800
#T = 0.2
T = l3fact
clipCK = Array.new
movieCK = Array.new
query = Array.new
firstpass = 0
uniqCounter = Array.new
@@TPCounter = 0

print("[#{l3fact}] Searching for #{sourceVideo}...\n")

videoArray.each do |video|

	p "Analyzing #{video}" if debug

	movieSecs = Array.new
	  
	####CLIP WE WANT TO LOOK FOR (PATTERN TO SEARCH)
	#
	if sourceVideo == video
		if dist.empty?
			fps = db.execute( "select * from allmovies where name = \"#{video}\"")[0][2].to_f/100.0
			raise SQLException if fps < 1 || fps == nil
		else
			ofps = orig_db.execute( "select * from allmovies where name = \"#{video}\"")[0][2].to_f/100.0
			raise SQLException if ofps < 1 || ofps == nil
		end
		
		begin
			if dist.empty?
				clipCK = db.execute( "select b1,b2,b3,b4,b5,b6,b7,b8 from \"#{video}\" where frame >= #{firstSec*fps} and frame < #{(firstSec*fps)+K}" )
			else
				clipCK = orig_db.execute( "select b1,b2,b3,b4,b5,b6,b7,b8 from \"#{video}\" where frame >= #{firstSec*ofps} and frame < #{(firstSec*ofps)+K}" )
			end
		rescue
			raise RuntimeError, "Video is not in database! Did you import the file beforehand?"
		end
	
		print("Using as source video:#{video}\n")
	end
	
	fps = db.execute( "select * from allmovies where name = \"#{video}\"")[0][2].to_f
	raise SQLException if fps < 1 || fps == nil

	#movieSecs = db.execute( "select frame from \"#{video}\" where b2 > #{clipCK[0][1].to_f-T} and b2 < #{clipCK[0][1].to_f+T} ")#and b7 > #{clipCK[0][6].to_f-T} and b7 < #{clipCK[0][6].to_f+T}")
	movieSecs = db.execute( "select frame from \"#{video}\" where b1 > #{clipCK[0][0].to_f-T} and b1 < #{clipCK[0][0].to_f+T} and b2 > #{clipCK[0][1].to_f-T} and b2 < #{clipCK[0][1].to_f+T} and b3 > #{clipCK[0][2].to_f-T} and b3 < #{clipCK[0][2].to_f+T} and b4 > #{clipCK[0][3].to_f-T} and b4 < #{clipCK[0][3].to_f+T} and b5 > #{clipCK[0][4].to_f-T} and b5 < #{clipCK[0][4].to_f+T} and b6 > #{clipCK[0][5].to_f-T} and b6 < #{clipCK[0][5].to_f+T} and b7 > #{clipCK[0][6].to_f-T} and b7 < #{clipCK[0][6].to_f+T} and b8 > #{clipCK[0][7].to_f-T} and b8 < #{clipCK[0][7].to_f+T}" )
	
	##
	#Now we search the big MOVIE sections to find our sequence

	#p movieSecs
	print("Seaching video:#{video} (found #{movieSecs.size} neighbors)\n") if movieSecs.size != 0 && debug

	#p movieSecs.size
	
	#compare clipCK with each result from query+K following elements
	prev = -(K/2)
	(0..movieSecs.size-1).each do |s|
		#p "#{movieSecs[s]}:" if debug
		sum = 0
		query = db.execute( "select b1,b2,b3,b4,b5,b6,b7,b8 from \"#{video}\" where frame >= #{movieSecs[s][0].to_i} and frame < #{movieSecs[s][0].to_i+(K)}" )

		(0..[query.size-1,clipCK.size-1].min).each do |f|
			sum += vectD(clipCK[f],query[f])
		end
		
		aux = movieSecs[s][0].to_i
		if sum < thresh
			if prev+(K/2) < aux
				puts("#{video} [#{aux} #{aux/(fps/100)}]=#{sum}") if sum < thresh && min == false
				hitCounter += 1 if sum < thresh
				uniqCounter << video
				@@TPCounter += 1 if sourceVideo == video
			end
			prev = aux
		end
		
	end
	
	
end
db.close()

print("Hits found: #{hitCounter} Unique hits found: #{uniqCounter.uniq.size} TPCounter: #{@@TPCounter}\n")
print("Test run-time for #{videoArray.size} movies was ","%5.2f" % (Time.new-stime), " seconds\n")
puts("")