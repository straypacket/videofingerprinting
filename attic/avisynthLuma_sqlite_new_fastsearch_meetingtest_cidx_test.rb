#Usage
#avisynthLuma [avg|diff] sourceVideo start length {-debug|-reverse}

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
subtitle = false
reverse = false
debug = false
debug1 = false
@@param = 0.1
linux = false
sqlite = false
sqlite_import = false
uprelem = 0.0
threeTables = false
cidx = false

#Path where the videos/logs are
path = 'C:/AviSynthVideos/'

(4..ARGV.size-1).each do |arg|
  if ARGV[arg] == "-debug"
    puts("Debug ON")
    debug = true
  elsif ARGV[arg] == "-reverse"
    puts("Reverse ON")
    reverse = true
  elsif ARGV[arg] == "-debug1"
    puts("Debug1 ON")
    debug1 = true
  elsif ARGV[arg] == "-linux"
    linux = true
    path = '/mnt/AviSynthVideos/'
  elsif ARGV[arg] == "-test"
    @@param = ARGV[arg+1].to_f 
  elsif ARGV[arg] == "-sqlite"
    puts("SQLite ON")
    sqlite = true
  elsif ARGV[arg] == "-sqlite_import"
    puts("SQLite import ON")
    sqlite_import = true
  elsif ARGV[arg] == "-prelem"
    uprelem = ARGV[arg+1].to_f
    puts("Test mode ON (prelem=#{uprelem})")
  elsif ARGV[arg] == "-3t"
    puts("Three tables per Movie ON")
    threeTables = true
  elsif ARGV[arg] == "-cidx"
    puts("Chroma index ON")
    cidx = true
  elsif ARGV[arg] == "-way"
    way = ARGV[arg+1].to_f
    puts("Selecting way (prelem=#{way})")
  #else
  #  raise RuntimeError, "Illegal command!"
  end
end

#Remaining auxiliary variables
#
method = ARGV[0]
sourceVideo = ARGV[1]
Dir.chdir(path)
videoArray = Array.new
aux = Dir.glob('*.{mp4}.log2')
aux.each do |file|
  filename = file.split(".")[0]+"."+file.split(".")[1]
  videoArray << filename
end

#for debug (to use while crawler is still running)
#videoArray.sort!
#videoArray.pop

videoArray.reverse! if reverse

#Exception control
raise RuntimeError, "Empty video directory!" if videoArray.empty? 
raise RuntimeError, "Please use avg or diff as first mandatory argument and the source video as the second argument!\nThe correct command line usage is: avisynthLuma [avg|diff] sourceVideo {-debug|-reverse|}" if ARGV.empty? || ARGV.size < 2

hitCounter = 0

##searchSeqArray operations
#
#firstSec = (15*rand(4))
firstSec = ARGV[2].to_i
@@lengthSec = ARGV[3].to_i
#these arrays are already the average of each second or part
searchSeqArrayLumaIni = Array.new
searchSeqArrayChromaUIni = Array.new
searchSeqArrayChromaVIni = Array.new
#total movie arrays
fps = 0.0
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

##SQLite vars
#
if sqlite
  db = SQLite3::Database.new( "test.db" ) if !linux
  db = SQLite3::Database.new( "/home/gsc/test.db" ) if linux
  db = SQLite3::Database.new( "/home/gsc/test_newtable_#{@@param}_lut.db" ) if linux && ( sqlite || sqlite_import )
  db = SQLite3::Database.new( "/home/gsc/test_newtable_#{@@param}_cidx_lut.db" ) if linux && ( sqlite || sqlite_import ) && cidx
  db = SQLite3::Database.new( "/home/gsc/test_3tablepermovie_#{@@param}_lut.db" ) if linux && threeTables && ( sqlite || sqlite_import )
  #
  begin
    if sqlite_import
      db.execute("create table allmovies (allmovieskey INTEGER PRIMARY KEY,name TEXT,fps int)")
      db.execute("PRAGMA count_changes = OFF")
    end
    db.execute("PRAGMA synchronous = OFF") if !sqlite_import
    puts("Creating new allmovies table") if sqlite_import
  rescue
    puts("Allmovies table already exists")
  end
  
  begin
    if sqlite_import
	  db.execute("create table hashluma (avg_range int, movies TEXT)")
	  db.execute("create table hashcu (avg_range int, movies TEXT)")
	  db.execute("create table hashcv (avg_range int, movies TEXT)")
	  print("Creating Hash tables ...")
	  (0..254).each do |n|
		db.execute( "insert into hashluma (avg_range) values (\"#{n}\")")
		db.execute( "insert into hashcu (avg_range) values (\"#{n}\")")
		db.execute( "insert into hashcv (avg_range) values (\"#{n}\")")
	  end
	  puts(" done")
    end
  rescue
    puts("Hash tables already exists")
  end
end

##CODE
#

#Normalization of _bounded_ vectors
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
      temp[aux] = (array[a] - lower)/(higher-lower)
      aux += 1
    end
  else
    extra = bound-(array.size-1)
    (array.size-length*@@part+extra..array.size-1).each do |a|
      temp[aux] = (array[a] - lower)/(higher-lower)
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
      array[aux] = array[a] if array[a] != nil && higher == lower
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

#Cluster information array
def arrayCluster(array,param)
  arrayCluster = Hash.new()
  c = 0
  aux = 0
  
  (0..array.size-2).each do |elem|
    arrayCluster[c] = 0 if aux == 0
    #if we're looking for a piece in the DB where @@lengthSec has no min/max normalization gives problems.
    #therefore, every @@lengthSec*0.4 we also create a new index
    #TODO: play with this 0.5 threshold
    if ((array[c].to_f - array[elem].to_f).abs > array[c].to_f*param || aux >= @@lengthSec*0.4)
      arrayCluster[c] = arrayCluster[c].to_f if aux == 0
      arrayCluster[c] = arrayCluster[c].to_f*1.0/aux if aux > 0
      aux = 0
      c = elem
    end
    arrayCluster[c] = 0 if aux == 0
    arrayCluster[c] += array[elem].to_f
    aux += 1
  end
  arrayCluster[c] = arrayCluster[c] if aux == 0
  arrayCluster[c] = arrayCluster[c]*1.0/aux if aux > 0
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

idxDistTimeLClip = Array.new
idxDistTimeCuClip = Array.new
idxDistTimeCvClip = Array.new
idxDistLumaClip = Array.new
idxDistCuClip = Array.new
idxDistCvClip = Array.new
idxDistTimeLMovie = Array.new
idxDistTimeCuMovie = Array.new
idxDistTimeCvMovie = Array.new
idxDistLumaMovie = Array.new
idxDistCuMovie = Array.new
idxDistCvMovie = Array.new

toSearchL = Hash.new
toSearchCu = Hash.new
toSearchCv = Hash.new

analyzedVideosCounter = 0

videoArray.each do |video|
  #re-init params
  fps = 0
  lumaArrayFrames = Array.new
  lumaArraySec = Array.new
  lumaArraySecCluster = Hash.new
  chromaUArrayFrames = Array.new
  chromaUArraySec = Array.new
  chromaUArraySecCluster = Hash.new
  chromaVArrayFrames = Array.new
  chromaVArraySec = Array.new
  chromaVArraySecCluster = Hash.new
  
  #Exception control
  raise RuntimeError, "No log file for #{video}! Did the analysis complete successfuly?" if File.exists?(path + video + ".log2") == false
  
  if sqlite_import  
    #Extract the results
    log = File.open(path + video + ".log2","r")
    puts("Reading #{video}.log2") if debug
    
    log.each do |line|
      if line =~ /^fps/
        fps = line.split(" ")[1].to_f
        raise RuntimeError, "Wrong FPS value for file #{video}" if fps.nan?
        fps = fps.to_i
        puts("Reading FPS off log file (#{fps})") if debug
      else
        aux = line.split(";")
        lumaArrayFrames[aux[0].to_i] = aux[2] if method == "avg"
        lumaArrayFrames[aux[0].to_i] = aux[3] if method == "diff"
        chromaUArrayFrames[aux[0].to_i] = aux[4]
        chromaVArrayFrames[aux[0].to_i] = aux[5]
      end
    end
    log.close
    
    raise RuntimeError, "Wrong FPS value for file #{video}" if fps == 0.0
    
    #### This will be the huge MOVIE we want to compare to 
    ##populate the average PART arrays *ArraySec[]
    print("Movie #{video} has ", (lumaArrayFrames.size-1)/(fps*@@part), " parts and each part is divided into ", (fps/@@part).to_int, " frames\n") if debug
    (0..((lumaArrayFrames.size-1)/(fps*@@part)-1)).each do |p| #  number of parts per movie
      avgLuma = avgChromaU = avgChromaV = 0.0
      (0..(fps/@@part)-1).each do |f| #  # of frames per part
        avgLuma += lumaArrayFrames[((fps/@@part)*p)+f].to_f
        avgChromaU += chromaUArrayFrames[((fps/@@part)*p)+f].to_f
        avgChromaV += chromaVArrayFrames[((fps/@@part)*p)+f].to_f
      end
      
      #average the values
      lumaArraySec[p] = ("%3.2f"%(avgLuma/fps*@@part)).to_f
      chromaUArraySec[p] = ("%3.2f"%(avgChromaU/fps*@@part)).to_f
      chromaVArraySec[p] = ("%3.2f"%(avgChromaV/fps*@@part)).to_f
    end
    
	#we can now insert the info into the DB
	
	begin
      db.execute( "delete from allmovies where name = \"#{video}\"")
    rescue
      puts("Movie #{movie} was already not in the DB, ignore this ...")
    end
    db.execute( "insert into allmovies (name,fps) values (\"#{video}\",#{(fps*100).to_i})")
    fps = fps.to_i
	
	mid = db.execute( "select * from allmovies where name = \"#{video}\"")[0][0].to_i
	
    c = nil
    if !threeTables
      lumaArraySecCluster = arrayCluster(lumaArraySec,@@param) if !cidx
      lumaArraySecCluster = arrayCluster(chromaUArraySec,@@param) if cidx
      #chromaUArraySecCluster = arrayCluster(chromaUArraySec,@@param)
      #chromaVArraySecCluster = arrayCluster(chromaVArraySec,@@param)
      begin
        db.execute( "BEGIN" )
        c = db.execute( "select count(*) from \"#{video}\"" )[0][0].to_i
        raise SQLException if sqlite_import
      rescue
        keys = lumaArraySecCluster.keys.sort
        db.execute("drop table \"#{video}\"") if c != nil
        db.execute("create table \"#{video}\" (s_end int, luma int, chromau int, chromav int)")
        (0..keys.size-2).each do |x| 
          #Convert values to 2-byte integers [0-255].00 * 100 <= 25599 which is lower than 65535 (thanks Christian!)
          avgLuma = (lumaArraySecCluster[keys[x]]*100).to_i
          avgChromaU = (chromaUArraySec[keys[x]]*100).to_i if !cidx
          avgChromaU = (lumaArraySec[keys[x]]*100).to_i if cidx
          avgChromaV = (chromaVArraySec[keys[x]]*100).to_i
          #insert in DB
          db.execute( "insert into \"#{video}\" (s_end,luma,chromau,chromav) values (#{keys[x]},#{avgLuma},#{avgChromaU},#{avgChromaV})") if !cidx
          db.execute( "insert into \"#{video}\" (s_end,luma,chromau,chromav) values (#{keys[x]},#{avgChromaU},#{avgLuma},#{avgChromaV})") if cidx
		  #append to "hashtables"
		  prev = db.execute( "select * from hashluma where avg_range = \"#{(avgLuma/100.0).round}\"" )[0][1]
		  db.execute( "update hashluma set movies = \"#{prev.to_s+mid.to_s+":"+(keys[x+1]-keys[x]).to_s+","}\" where avg_range = \"#{(avgLuma/100.0).round}\"" ) if prev.to_s.split(',').index(mid.to_s) == nil
		  #
		  prev = db.execute( "select * from hashcu where avg_range = \"#{(avgChromaU/100.0).round}\"" )[0][1]
		  db.execute( "update hashcu set movies = \"#{prev.to_s+mid.to_s+":"+(keys[x+1]-keys[x]).to_s+","}\" where avg_range = \"#{(avgChromaU/100.0).round}\"" ) if prev.to_s.split(',').index(mid.to_s) == nil
		  #
		  prev = db.execute( "select * from hashcv where avg_range = \"#{(avgChromaV/100.0).round}\"" )[0][1]
		  db.execute( "update hashcv set movies = \"#{prev.to_s+mid.to_s+":"+(keys[x+1]-keys[x]).to_s+","}\" where avg_range = \"#{(avgChromaV/100.0).round}\"" ) if prev.to_s.split(',').index(mid.to_s) == nil
        end
        #insert last element
        db.execute( "insert into \"#{video}\" (s_end,luma,chromau,chromav) values (#{keys[keys.size-1]},-1,-1,-1)")
      end
    end
    
    if threeTables
      lumaArraySecCluster = arrayCluster(lumaArraySec,@@param)
      chromaUArraySecCluster = arrayCluster(chromaUArraySec,@@param)
      chromaVArraySecCluster = arrayCluster(chromaVArraySec,@@param)
      ##Luma
      begin
        db.execute( "BEGIN" )
        c = db.execute( "select count(*) from \"#{video}_l\"" )[0][0].to_i
        raise SQLException if sqlite_import
      rescue
        keys = lumaArraySecCluster.keys.sort
        db.execute("drop table \"#{video}_l\"") if c != nil
        db.execute("create table \"#{video}_l\" (s_end int, luma int)")
        (0..keys.size-2).each do |x| 
          #Convert values to 2-byte integers [0-255].00 * 100 <= 25599 which is lower than 65535 (thanks Christian!)
          avg = (lumaArraySecCluster[keys[x]]*100).to_i
          #insert in DB
          db.execute( "insert into \"#{video}_l\" (s_end,luma) values (#{keys[x]},#{avg})")
		  #append to "hashtables"
		  prev = db.execute( "select * from hashluma where avg_range = \"#{(avg/100.0).round}\"" )[0][1]
		  db.execute( "update hashluma set movies = \"#{prev.to_s+mid.to_s+":"+(keys[x+1]-keys[x]).to_s+","}\" where avg_range = \"#{(avg/100.0).round}\"" ) if prev.to_s.split(',').index(mid.to_s) == nil
        end
        #insert last element
        db.execute( "insert into \"#{video}_l\" (s_end,luma) values (#{keys[keys.size-1]},-1)")
      end     

      ##ChromaU
      begin
        db.execute( "BEGIN" )
        c = db.execute( "select count(*) from \"#{video}_cu\"" )[0][0].to_i
        raise SQLException if sqlite_import
      rescue
        keys = chromaUArraySecCluster.keys.sort
        db.execute("drop table \"#{video}_cu\"") if c != nil
        db.execute("create table \"#{video}_cu\" (s_end int, chromau int)")
        (0..keys.size-2).each do |x| 
          #Convert values to 2-byte integers [0-255].00 * 100 <= 25599 which is lower than 65535 (thanks Christian!)
          avg = (chromaUArraySecCluster[keys[x]]*100).to_i
          #insert in DB
          db.execute( "insert into \"#{video}_cu\" (s_end,chromau) values (#{keys[x]},#{avg})")
		  #append to "hashtables"
		  prev = db.execute( "select * from hashcu where avg_range = \"#{(avg/100.0).round}\"" )[0][1]
		  db.execute( "update hashcu set movies = \"#{prev.to_s+mid.to_s+":"+(keys[x+1]-keys[x]).to_s+","}\" where avg_range = \"#{(avg/100.0).round}\"" ) if prev.to_s.split(',').index(mid.to_s) == nil        
        end
        #insert last element
        db.execute( "insert into \"#{video}_cu\" (s_end,chromau) values (#{keys[keys.size-1]},-1)")
      end      

      ##ChromaV
      begin
        db.execute( "BEGIN" )
        c = db.execute( "select count(*) from \"#{video}_cv\"" )[0][0].to_i
        raise SQLException if sqlite_import
      rescue
        keys = chromaVArraySecCluster.keys.sort
        db.execute("drop table \"#{video}_cv\"") if c != nil
        db.execute("create table \"#{video}_cv\" (s_end int, chromav int)")
        (0..keys.size-2).each do |x| 
          #Convert values to 2-byte integers [0-255].00 * 100 <= 25599 which is lower than 65535 (thanks Christian!)
          avg = (chromaVArraySecCluster[keys[x]]*100).to_i
          #insert in DB
          db.execute( "insert into \"#{video}_cv\" (s_end,chromav) values (#{keys[x]},#{avg})")
		  #append to "hashtables"
		  prev = db.execute( "select * from hashcv where avg_range = \"#{(avg/100.0).round}\"" )[0][1]
		  db.execute( "update hashcv set movies = \"#{prev.to_s+mid.to_s+":"+(keys[x+1]-keys[x]).to_s+","}\" where avg_range = \"#{(avg/100.0).round}\"" ) if prev.to_s.split(',').index(mid.to_s) == nil
        end
        #insert last element
        db.execute( "insert into \"#{video}_cv\" (s_end,chromav) values (#{keys[keys.size-1]},-1)")
      end         
    end
    
    savings += (1-((lumaArraySecCluster.size.to_i-1)*1.0/(lumaArraySec.size.to_i-1)*1.0))*100.0
    
    db.execute( "END" )
    
  end
  
  if sqlite
    begin
      fps = db.execute( "select * from allmovies where name = \"#{video}\"")[0][2].to_f
      raise SQLException if fps < 1 || fps == nil
      fps /= 100
      fps = fps.to_i
    rescue
      log = File.open(path + video + ".log2","r")
      log.each do |line|
        if line =~ /^fps/
          fps = line.split(" ")[1].to_f
          raise RuntimeError, "Wrong FPS value for file #{video}" if fps.nan?
          puts("Reading FPS off log file (#{fps})") if debug
          db.execute( "delete from allmovies where name = \"#{video}\"")
          db.execute( "insert into allmovies (name,fps) values (\"#{video}\",#{(fps*100).to_i})")
          fps = fps.to_i
        end
      end
      log.close
    end
	
	##Stats
	#
	#(1..255).each do |x|
	#	count = db.execute( "select * from hashluma where avg_range = \"#{x}\"" )[0][1]
	#	puts("#{x} #{count.split(',').size-1}") if count != nil
	#	puts("#{x} 0") if count == nil
	#end

    ## DB fetch and array reconstruction
    #
    lumaArraySec.clear
    chromaUArraySec.clear
    chromaVArraySec.clear
    lumaArraySecCluster.clear
    chromaUArraySecCluster.clear
    chromaVArraySecCluster.clear
	
	mid = db.execute( "select * from allmovies where name = \"#{video}\"")[0][0].to_i
    
    if !threeTables
      #query will be a bi-dimensional array with [time] x [luma,chromau,chromav]
      begin
      query = db.execute( "select * from \"#{video}\"" )
      rescue
        puts("Video is not in database! Did you run the -sqlite_import flag beforehand?")
        return
      end
      rows = query[0..-1].size
      (0..rows-2).each do |r|
        lumaArraySecCluster[query[r][0].to_i] = query[r][1].to_f
        chromaUArraySecCluster[query[r][0].to_i] = query[r][2].to_f
        chromaVArraySecCluster[query[r][0].to_i] = query[r][3].to_f
        (query[r][0].to_i..(query[r+1][0].to_i)-1).each do |l|
          lumaArraySec[l] = (query[r][1].to_i)/100.0
          chromaUArraySec[l] = (query[r][2].to_i)/100.0
          chromaVArraySec[l] = (query[r][3].to_i)/100.0
        end
      end
      lumaArraySec[query[rows-1][0].to_i] = (query[rows-2][1].to_i)/100.0
      chromaUArraySec[query[rows-1][0].to_i] = (query[rows-2][2].to_i)/100.0
      chromaVArraySec[query[rows-1][0].to_i] = (query[rows-2][3].to_i)/100.0
    end
    
    if threeTables
      ##Luma
      begin
      query = db.execute( "select * from \"#{video}_l\"" )
      rescue
        puts("Video is not in database! Did you run the -sqlite_import flag beforehand?")
        return
      end
      rows = query[0..-1].size
      (0..rows-2).each do |r|
        lumaArraySecCluster[query[r][0].to_i] = query[r][1].to_f
        (query[r][0].to_i..(query[r+1][0].to_i)-1).each do |l|
          lumaArraySec[l] = (query[r][1].to_i)/100.0
        end
      end
      lumaArraySec[query[rows-1][0].to_i] = (query[rows-2][1].to_i)/100.0
      
      ##ChromaU
      begin
      query = db.execute( "select * from \"#{video}_cu\"" )
      rescue
        puts("Video is not in database! Did you run the -sqlite_import flag beforehand?")
        return
      end
      rows = query[0..-1].size
      (0..rows-2).each do |r|
        chromaUArraySecCluster[query[r][0].to_i] = query[r][1].to_f
        (query[r][0].to_i..(query[r+1][0].to_i)-1).each do |l|
          chromaUArraySec[l] = (query[r][1].to_i)/100.0
        end
      end
      chromaUArraySec[query[rows-1][0].to_i] = (query[rows-2][1].to_i)/100.0
      
      ##ChromaV
      begin
      query = db.execute( "select * from \"#{video}_cv\"" )
      rescue
        puts("Video is not in database! Did you run the -sqlite_import flag beforehand?")
        return
      end
      rows = query[0..-1].size
      (0..rows-2).each do |r|
        chromaVArraySecCluster[query[r][0].to_i] = query[r][1].to_f
        (query[r][0].to_i..(query[r+1][0].to_i)-1).each do |l|
          chromaVArraySec[l] = (query[r][1].to_i)/100.0
        end
      end
      chromaVArraySec[query[rows-1][0].to_i] = (query[rows-2][1].to_i)/100.0
      
    end
    
  end
  
  print("Video has a length of #{(lumaArraySec.size-1)/@@part} seconds and each second is divided in #{@@part} parts\n") if debug
  
  ####VIDEO WE WANT TO LOOK FOR (PATTERN TO SEARCH)
  #Populating our Sequence array, this is what we want to find when searching other movies
  #We use the PARTS arrays just created for this, i.e. the *ArraySec[] arrays
  
  #only use source video, passed by ARGV[1]
  if sourceVideo == video
    aux = 0
    print("Using as source video:#{video}\n") if debug
    if (lumaArraySec.size-1)/@@part >= firstSec+@@lengthSec
      ((firstSec*@@part)..((firstSec*@@part)+((@@lengthSec*@@part)-1))).each do |x|
        print("Populating position #{aux} with #{lumaArraySec[x]} [#{firstSec}-#{firstSec+@@lengthSec-1}]\n") if debug
        searchSeqArrayLumaIni[aux] = lumaArraySec[x]
        searchSeqArrayChromaUIni[aux] = chromaUArraySec[x]
        searchSeqArrayChromaVIni[aux] = chromaVArraySec[x]
        
        aux += 1
      end
    else
      puts("WARNING! The video you're looking at is too short for the chosen time slot search!\nLooking for [#{firstSec}~#{firstSec+@@lengthSec}] in #{video} movie which has a size of [0~#{lumaArraySec.size-1}].") if (lumaArraySec.size-1)/@@part < firstSec+@@lengthSec
      print("Video has a length of #{(lumaArraySec.size-1)/@@part} seconds and each second is divided in #{@@part} parts\n") if debug
      raise RuntimeError, "Video #{video} has no such segment [#{firstSec}~#{firstSec+@@lengthSec}] or is too small (#{lumaArraySec.size-1-firstSec})" if (lumaArraySec.size-1-firstSec < 3)
      puts("Using #{video}:[#{firstSec}~#{lumaArraySec.size-1}] instead (#{lumaArraySec.size-1-firstSec} secs).")
      @@lengthSec = lumaArraySec.size-1-firstSec
      ((firstSec*@@part)..((firstSec*@@part)+((@@lengthSec*@@part)-1))).each do |x|
        print("Populating position #{aux} with #{lumaArraySec[x]} [#{firstSec}-#{firstSec+@@lengthSec-1}]\n") if debug
        searchSeqArrayLumaIni[aux] = lumaArraySec[x]
        searchSeqArrayChromaUIni[aux] = chromaUArraySec[x]
        searchSeqArrayChromaVIni[aux] = chromaVArraySec[x]
        
        aux += 1
      end
    end

#=begin
    test = Hash.new
    test = arrayCluster(searchSeqArrayLumaIni,@@param)
    test1 = Hash.new
    test1 = arrayCluster(searchSeqArrayChromaUIni,@@param)
    test2 = Hash.new
    test2 = arrayCluster(searchSeqArrayChromaVIni,@@param)

    #distance between IDXs and Lumas for CLIP
    auxClipArray = Array.new
    auxClipArray = test.sort
    auxClipArray1 = Array.new
    auxClipArray1 = test1.sort
    auxClipArray2 = Array.new
    auxClipArray2 = test2.sort
    
    (0..test.size-2).each do |d|
      idxDistTimeLClip << auxClipArray[d+1][0]-auxClipArray[d][0]
      idxDistLumaClip << (auxClipArray[d+1][1]-auxClipArray[d][1]).abs
    end
    (0..test1.size-2).each do |d|
      idxDistTimeCuClip << auxClipArray1[d+1][0]-auxClipArray1[d][0]
      idxDistCuClip << (auxClipArray1[d+1][1]-auxClipArray1[d][1]).abs
    end
    (0..test2.size-2).each do |d|
      idxDistTimeCvClip << auxClipArray2[d+1][0]-auxClipArray2[d][0]
      idxDistCvClip << (auxClipArray2[d+1][1]-auxClipArray2[d][1]).abs
    end
    
    idxDistTimeLClip << auxClipArray[auxClipArray.size-1][0]-auxClipArray[auxClipArray.size-2][0]
    idxDistTimeCuClip << auxClipArray1[auxClipArray1.size-1][0]-auxClipArray1[auxClipArray1.size-2][0]
    idxDistTimeCvClip << auxClipArray2[auxClipArray2.size-1][0]-auxClipArray2[auxClipArray2.size-2][0]
    idxDistLumaClip << (auxClipArray[auxClipArray.size-1][1]-auxClipArray[auxClipArray.size-2][1]).abs
    idxDistCuClip << (auxClipArray1[auxClipArray1.size-1][1]-auxClipArray1[auxClipArray1.size-2][1]).abs
    idxDistCvClip << (auxClipArray2[auxClipArray2.size-1][1]-auxClipArray2[auxClipArray2.size-2][1]).abs
    #idxDistLumaClip = norm(idxDistLumaClip)
#=end
 
    #Normalize the CLIP array
    searchSeqArrayLumaIni = norm(searchSeqArrayLumaIni)
    searchSeqArrayChromaUIni = norm(searchSeqArrayChromaUIni)
    searchSeqArrayChromaVIni = norm(searchSeqArrayChromaVIni)
  
  end
  ####
  

  print("Seaching video:#{video}\n") if debug
  puts("-------------------------------------------------------------") if debug
  
  realFrame = -1
  auxDiffLuma = Array.new
  auxDiffCu = Array.new
  auxDiffCv = Array.new
  auxSqrtLuma = Array.new
  auxSqrtCu = Array.new
  auxSqrtCv = Array.new
  taniLuma = Array.new
  taniChromaU = Array.new
  taniChromaV = Array.new
  
  #now that we have searchSeqArray[] and *ArraySec[], bruteforce the whole movie to find our sequence
  #we start at second 0 and compare every second of our searchSeqArray[] movie to the one of the lumaArraySec[] clip, sequentially
  #then proceed to frame 1, then frame 2, etc, etc

  #distance between IDXs for MOVIE
  auxArray = Array.new
  auxArray = lumaArraySecCluster.sort
  auxArray1 = Array.new
  auxArray1 = chromaUArraySecCluster.sort
  auxArray2 = Array.new
  auxArray2 = chromaVArraySecCluster.sort  
  idxDistTimeLMovie.clear
  idxDistTimeCuMovie.clear
  idxDistTimeCvMovie.clear
  idxDistLumaMovie.clear
  idxDistCuMovie.clear
  idxDistCvMovie.clear
  (1..auxArray.size-2).each do |d|
    idxDistTimeLMovie << auxArray[d+1][0]-auxArray[d][0]
    idxDistLumaMovie << (auxArray[d+1][1]-auxArray[d][1]).abs/100.0
  end
  (1..auxArray1.size-2).each do |d|
    idxDistTimeCuMovie << auxArray1[d+1][0]-auxArray1[d][0]
    idxDistCuMovie << (auxArray1[d+1][1]-auxArray1[d][1]).abs/100.0
  end
  (1..auxArray2.size-2).each do |d|
    idxDistTimeCvMovie << auxArray2[d+1][0]-auxArray2[d][0]
    idxDistCvMovie << (auxArray2[d+1][1]-auxArray2[d][1]).abs/100.0
  end
  idxDistTimeLMovie << auxArray[auxArray.size-1][0]-auxArray[auxArray.size-2][0]
  idxDistTimeCuMovie << auxArray1[auxArray1.size-1][0]-auxArray1[auxArray1.size-2][0]
  idxDistTimeCvMovie << auxArray2[auxArray2.size-1][0]-auxArray2[auxArray2.size-2][0]
  idxDistLumaMovie << (auxArray[auxArray.size-1][1]-auxArray[auxArray.size-2][1]).abs/100.0
  idxDistCuMovie << (auxArray1[auxArray1.size-1][1]-auxArray1[auxArray1.size-2][1]).abs/100.0
  idxDistCvMovie << (auxArray2[auxArray2.size-1][1]-auxArray2[auxArray2.size-2][1]).abs/100.0

#=begin
  ##Parameters to tune in this section:
  # - b_thresh (Luma and Chromas only)
  # - count >= idxDistClip.size-3 && countL >= idxDistClip.size-4
  
  b_val1 = false
  b_val2 = false
  #
  b_array = Array.new
  b_array1 = Array.new
  b_array2 = Array.new
  b_thresh = uprelem
  #
  aaux = Array.new

#=begin  
  ## Way 2
  if toSearchL.empty?
	#for every idx in the Clip, compare its Luma values with hash
	auxArray.each do |avg|
		#add movies with similar luma as the index to toSearch[]
		#p "select * from hashluma where avg_range = #{((avg[1].to_i/100.0).round)+0}"
		qArray = Array.new
		#qArray = db.execute( "select * from hashluma where avg_range between #{((avg[1].to_i/100.0).round)-10} and #{((avg[1].to_i/100.0).round)+10}" )
		qArray = db.execute( "select * from hashluma where avg_range = #{((avg[1].to_i/100.0).round)-0}" )
		(0..qArray.size-1).each do |e|
			qArray[e][1].to_s.split(',').sort.uniq.each do |tuple|
				#p aaux
				aaux = tuple.to_s.split(':')
				toSearchL[aaux[0].to_i] = Array.new if toSearchL.has_key?(aaux[0].to_i) == false
				toSearchL[aaux[0].to_i] << aaux[1].to_i
			end
		end
	end
  end
  aaux.clear
  
  #If b_val1 line is fully uncommented we will compare the sizes of the IDXs in Clips vs Movie.
  #While this brings more differentiation, it will result in a higher number of false negatives.
  #Therefore we only compare if the current movie has an average Luma (chromas?) that we are looking for
  #If not, we skip it
  if toSearchL[mid] != nil
	b_val1 = true if toSearchL.has_key?(mid) == true #&& (idxDistTimeLClip & toSearchL[mid]).sort.uniq == idxDistTimeLClip.sort.uniq
  end
  
  #p toSearchL

#  if toSearchCu.empty?
	#for every idx in the Clip, compare its ChromaU values with hash
#	auxArray1.each do |avg|
		#add movies with similar chromau as the index to toSearch[]
		#p "select * from hashcu where avg_range = #{((avg[1].to_i/100.0).round)+0}"
#		db.execute( "select * from hashcu where avg_range = #{((avg[1].to_i/100.0).round)+0}" )[0][1].to_s.split(',').sort.uniq.each do |tuple|
			#p aaux
#			aaux = tuple.to_s.split(':')
#			toSearchCu[aaux[0].to_i] = Array.new if toSearchCu.has_key?(aaux[0].to_i) == false
#			toSearchCu[aaux[0].to_i] << aaux[1].to_i
			#toSearchCu[aaux[0].to_i].sort!.uniq!
#		end
#	end
#  end
#  aaux.clear
  
#  if toSearchCv.empty?
	#for every idx in the Clip, compare its ChromaU values with hash
#	auxArray2.each do |avg|
		#add movies with similar chromau as the index to toSearch[]
		#p "select * from hashcu where avg_range = #{((avg[1].to_i/100.0).round)+0}"
#		db.execute( "select * from hashcv where avg_range = #{((avg[1].to_i/100.0).round)+0}" )[0][1].to_s.split(',').sort.uniq.each do |tuple|
			#p aaux
#			aaux = tuple.to_s.split(':')
#			toSearchCv[aaux[0].to_i] = Array.new if toSearchCv.has_key?(aaux[0].to_i) == false
#			toSearchCv[aaux[0].to_i] << aaux[1].to_i
#			#toSearchCv[aaux[0].to_i].sort!.uniq!
#		end
#	end
#  end
#  aaux.clear

  #b_val = true if toSearchL.has_key?(mid) == true && toSearchCu.has_key?(mid) == true && toSearchCv.has_key?(mid) == true
#=end
#
#=begin
  if b_val1 == true #&& toSearchL.has_key?(mid) == true #&& toSearchCu.has_key?(mid) == true && toSearchCv.has_key?(mid) == true
    #p "--"
    #p video
	#p (toSearchL[mid].sort.size-idxDistTimeLMovie.sort.size).abs
	#
	##Idea: use number of elements that have a value of 1, number of elements that have a value of 2, etc
	#
    #if (toSearchL[mid].sort.size-idxDistTimeLMovie.sort.size).abs < 50
	  #find CLIP IDXs in MOVIE IDXs
	  #most F'ed up hack for MAX() I've ever seen
	  (0..[idxDistTimeLMovie.size,idxDistTimeCuMovie.size,idxDistTimeCvMovie.size].max-1).each do |x|
		count = count1 = count2 = 0
		countL = 0
		countCu = 0
		countCv = 0
		
		#
		if x-1 <= idxDistTimeLMovie.size-idxDistTimeLClip.size
		  b_array = idxDistLumaMovie[x..x+idxDistTimeLClip.size-1]
		  (0..idxDistTimeLClip.size-2).each do |y|
			#p "L  T= #{video}: sec:#{auxArray[x+y][0]} idx:#{x} #{idxDistTimeLMovie[x+y]} == #{idxDistTimeLClip[y]}?  --  #{(b_array[y])} ~= #{(idxDistLumaClip[y])}?"
			count +=1 if idxDistTimeLMovie[x+y] == idxDistTimeLClip[y]
			countL += 1 if b_array[y] >= idxDistLumaClip[y]*(1-b_thresh) && b_array[y] <= idxDistLumaClip[y]*(1+b_thresh)
		  end
		end
		
#		if x-1 <= idxDistTimeCuMovie.size-idxDistTimeLClip.size
#		  b_array1 = idxDistCuMovie[x..x+idxDistTimeCuClip.size-1]
#		  (0..idxDistTimeCuClip.size-2).each do |y|
			#p "Cu T= #{video}: sec:#{auxArray1[x+y][0]} idx:#{x} #{idxDistTimeCuMovie[x+y]} == #{idxDistTimeCuClip[y]}?  --  #{(b_array1[y])} ~= #{(idxDistCuClip[y])}?"
#			count1 +=1 if idxDistTimeCuMovie[x+y] == idxDistTimeCuClip[y]
#			countCu += 1 if b_array1[y] >= idxDistCuClip[y]*(1-b_thresh) && b_array1[y] <= idxDistCuClip[y]*(1+b_thresh)
#		  end
#		end
		
#		if x-1 <= idxDistTimeCvMovie.size-idxDistTimeLClip.size
#		  b_array2 = idxDistCvMovie[x..x+idxDistTimeCvClip.size-1]
#		  (0..idxDistTimeCvClip.size-2).each do |y|
			#p "Cv T= #{video}: sec:#{auxArray2[x+y][0]} idx:#{x} #{idxDistTimeCvMovie[x+y]} == #{idxDistTimeCvClip[y]}?  --  #{(b_array2[y])} ~= #{(idxDistCvClip[y])}?"
#			count2 +=1 if idxDistTimeCvMovie[x+y] == idxDistTimeCvClip[y]
#			countCv += 1 if b_array2[y] >= idxDistCvClip[y]*(1-b_thresh) && b_array2[y] <= idxDistCvClip[y]*(1+b_thresh)
#		  end
#		end

		#p "L  #{video}: idx=#{x} sec:#{auxArray[x][0]} Count=#{count}/#{idxDistTimeLClip.size-1} CountL=#{countL}/#{idxDistTimeLClip.size-1}"
		#p "Cu #{video}: idx=#{x} sec:#{auxArray1[x][0]} Count=#{count1}/#{idxDistTimeCuClip.size-1} CountCu=#{countCu}/#{idxDistTimeCuClip.size-1}"
		#p "Cv #{video}: idx=#{x} sec:#{auxArray2[x][0]} Count=#{count2}/#{idxDistTimeCvClip.size-1} CountCv=#{countCv}/#{idxDistTimeCvClip.size-1}"
		#p "#{video}: idx=#{x} Count=#{count}/#{idxDistTimeLClip.size-1} CountL=#{countL}/#{idxDistTimeLClip.size-1}"

		if count >= idxDistTimeLClip.size-4 && countL >= idxDistTimeLClip.size-5
		  #p "#{video}: idx=#{x} Count=#{count}/#{idxDistTimeLClip.size-1} CountL=#{countL}/#{idxDistTimeLClip.size-1}"
		  b_val2 = true
		  break
		end

	  end
	#end
	
  end
  
#=end

  #If the clip we're looking for does not have the same time intervals, for the luma we're looking for, as the clip we want to find, discard it
  #if b_val1 == false
  if b_val2 == false 
    #break out of the movie loop, going for the next movie
	#p "Next!"
    next
  end

  analyzedVideosCounter += 1
  #puts("Searching #{toSearchCv.size} of 210 movies")

  #TODO: describe fast search text (wtf? thought it was here already)
  (0..(lumaArraySecCluster.keys.size - 2)).each do |idx|
    (lumaArraySecCluster.keys.sort[idx].to_i..(lumaArraySecCluster.keys.sort[idx+1].to_i)-1).each do |x|
      #p "Using clip from #{lumaArraySecCluster.keys.sort[idx].to_i} to #{(lumaArraySecCluster.keys.sort[idx+1].to_i)-1}"
      #p "Skipping from #{lumaArraySecCluster.keys.sort[idx-1].to_i} to #{(lumaArraySecCluster.keys.sort[idx].to_i-1)}"
      diffLuma = diffChromaU = diffChromaV = 0.0
      similarLumaAvg = similarChromaUAvg = similarChromaVAvg = 0.0
      diffLumaAvg = Array.new
      diffChromaVAvg = Array.new
      diffChromaUAvg = Array.new
      distLuma = Array.new
      distChromaU = Array.new
      distChromaV = Array.new
      
      partNumb = x%@@part
      realFrame += 1 if partNumb == 0
      
      ##normalize the block of the MOVIE we're looking at, until it does not exceeds the bounds
      tempArrayLuma = Array.new
      tempArrayChromaU = Array.new
      tempArrayChromaV = Array.new
      
      #If we exceed the end of the array do as if we were within the last bounds of the movie
      #BUT discard the last exceeding number of elements of the array
      bound = (@@lengthSec*@@part)+x-1
      tempArrayLuma = normBound(lumaArraySec,x,bound,@@lengthSec)
      tempArrayChromaU = normBound(chromaUArraySec,x,bound,@@lengthSec)
      tempArrayChromaV = normBound(chromaVArraySec,x,bound,@@lengthSec)
      
      #test = Hash.new
      #test = arrayCluster(searchSeqArrayLumaIni,@@param)
      #modify to only look for second IDX of searchSeqArray*
      searchSeqArrayLuma = searchSeqArrayLumaIni#[test.sort[1][0].to_i..-1]
      searchSeqArrayChromaU = searchSeqArrayChromaUIni#[test.sort[1][0].to_i..-1]
      searchSeqArrayChromaV = searchSeqArrayChromaVIni#[test.sort[1][0].to_i..-1]
      
      norm(tempArrayLuma)
      norm(tempArrayChromaU)
      norm(tempArrayChromaV)
      
      #test1 = Hash.new
      #test1 = arrayCluster(tempArrayLuma,@@param)
      #modify to only look for second IDX of searchSeqArray*
      #tempArrayLuma = tempArrayLuma[test1.sort[1][0].to_i..-1]
      #tempArrayChromaU = tempArrayChromaU[test1.sort[1][0].to_i..-1]
      #tempArrayChromaV = tempArrayChromaV[test1.sort[1][0].to_i..-1]
      
      #When reaching the end of the array, we had a condition where the values outside of the array would be compared
      #Ex: Searching for 10 second blocks in a 60 second movie, would give us a search between [55-65]. 
      #Also, we don't want to compare only 1 second (too many false positives). 5 seconds is the lowest piece we search.
      if ( lumaArraySec.size-x < @@lengthSec*@@part )
        bound = lumaArraySec.size-x-1
        searchSeqArrayLuma = searchSeqArrayLumaIni[0..bound]
        searchSeqArrayChromaU = searchSeqArrayChromaUIni[0..bound]
        searchSeqArrayChromaV = searchSeqArrayChromaVIni[0..bound]
      end
      
      ##ALGORITHMS

      ##tanimoto
      #
      taniLuma[x] = tanimoto(searchSeqArrayLuma, tempArrayLuma)
      taniChromaU[x] = tanimoto(searchSeqArrayChromaU, tempArrayChromaU)
      taniChromaV[x] = tanimoto(searchSeqArrayChromaV, tempArrayChromaV)
    
      ##Difference between CLIP and MOVIE
      #
      auxDiffLuma[x] = diff(searchSeqArrayLuma,tempArrayLuma)
      auxDiffCu[x] = diff(searchSeqArrayChromaU,tempArrayChromaU)
      auxDiffCv[x] = diff(searchSeqArrayChromaV,tempArrayChromaV)
    
      ##Distance between vectors
      #
      auxSqrtLuma[x] = vectD(searchSeqArrayLuma,tempArrayLuma)
      auxSqrtCu[x] = vectD(searchSeqArrayChromaU,tempArrayChromaU)
      auxSqrtCv[x] = vectD(searchSeqArrayChromaV,tempArrayChromaV)
    end
  end
  
  #normalize difference between vectors
  #auxDiffLuma = norm(auxDiffLuma)
  #auxDiffCu = norm(auxDiffCu)
  #auxDiffCv = norm(auxDiffCv)

  #normalize distance between vectors
  auxSqrtLuma = norm(auxSqrtLuma)
  auxSqrtCu = norm(auxSqrtCu)
  auxSqrtCv = norm(auxSqrtCv)
  
  realFrame = -1
  partNumb = 0
  
  maxSize = 1
  sleep = -1
  sleepT = -1
  score = 0.0
  scoreTani = 0.0
  scoreTotal = 0.0
  scoreP = 0.0
  
  taniLumaBuff = Array.new(maxSize,0.0)
  taniCuBuff = Array.new(maxSize,0.0)
  taniCvBuff = Array.new(maxSize,0.0)
  diffLumaBuff = Array.new(maxSize,1.0)
  diffCuBuff = Array.new(maxSize,1.0)
  diffCvBuff = Array.new(maxSize,1.0)
  sqrtLumaBuff = Array.new(maxSize,1.0)
  sqrtCuBuff = Array.new(maxSize,1.0)
  sqrtCvBuff = Array.new(maxSize,1.0)
  
  (0..(lumaArraySecCluster.keys.size - 2)).each do |idx|
    (lumaArraySecCluster.keys.sort[idx].to_i..(lumaArraySecCluster.keys.sort[idx+1].to_i)-1).each do |x|
      partNumb = x%@@part
      realFrame += 1 if partNumb == 0
      
      #Fast search
      if taniLuma[x] == nil
        #FIX to use partNumb
        realFrame += lumaArraySecCluster.keys.sort[idx+1].to_i-1-x
        break
      end
      
      diffLumaBuff[x%maxSize] = auxDiffLuma[x] if !auxDiffLuma[x].nan?
      diffCuBuff[x%maxSize] = auxDiffCu[x] if !auxDiffCu[x].nan?
      diffCvBuff[x%maxSize] = auxDiffCv[x] if !auxDiffCv[x].nan?
      sqrtLumaBuff[x%maxSize] = auxSqrtLuma[x] if !auxSqrtLuma[x].nan?
      sqrtCuBuff[x%maxSize] = auxSqrtCu[x] if !auxSqrtCu[x].nan?
      sqrtCvBuff[x%maxSize] = auxSqrtCv[x] if !auxSqrtCv[x].nan?
      
      taniLumaBuff[x%maxSize] = taniLuma[x] if !taniLuma[x].nan?
      taniCuBuff[x%maxSize] = taniChromaU[x] if !taniChromaU[x].nan?
      taniCvBuff[x%maxSize] = taniChromaV[x] if !taniChromaV[x].nan?
      
      thresh = 0.05
      thresh2 = 0.15
      taniThresh = 0.97
      taniThresh2 = 0.85
      
      ##Scoring
      #
      point = 0.25/6
      
      if diffLumaBuff.sort[0] <= thresh  && sleep == -1
        score += point
      elsif diffLumaBuff.sort[0] <= thresh2  && sleep == -1
        score += point/2
      end
      
      if sqrtLumaBuff.sort[0] <= thresh && sleep == -1
        score += point
      elsif sqrtLumaBuff.sort[0] <= thresh2  && sleep == -1
        score += point/2
      end
      
      if diffCuBuff.sort[0] <= thresh && sleep == -1
        score += point
      elsif diffCuBuff.sort[0] <= thresh2  && sleep == -1
        score += point/2
      end
      
      if sqrtCuBuff.sort[0] <= thresh && sleep == -1
        score += point
      elsif sqrtCuBuff.sort[0] <= thresh2  && sleep == -1
        score += point/2
      end
      
      if diffCvBuff.sort[0] <= thresh && sleep == -1
        score += point
      elsif diffCvBuff.sort[0] <= thresh2  && sleep == -1
        score += point/2
      end
      
      if sqrtCvBuff.sort[0] <= thresh && sleep == -1
        score += point
      elsif sqrtCvBuff.sort[0] <= thresh2  && sleep == -1
        score += point/2
      end
    
      point = 0.75/3
      
      if  taniLumaBuff.sort[maxSize-1] >= taniThresh && sleepT == -1
        scoreTani += point
      elsif taniLumaBuff.sort[maxSize-1] >= taniThresh2 && sleepT == -1
        scoreTani += point/2
      end
      
      if taniCuBuff.sort[maxSize-1] >= taniThresh && sleepT == -1
        scoreTani += point
      elsif taniCuBuff.sort[maxSize-1] >= taniThresh2 && sleepT == -1
        scoreTani += point/2
      end
      
      if taniCvBuff.sort[maxSize-1] >= taniThresh && sleepT == -1
        scoreTani += point
      elsif taniCvBuff.sort[maxSize-1] >= taniThresh2 && sleepT == -1
        scoreTani += point/2
      end
      
      scoreTotal = score+scoreTani
      
      #print(realFrame, ".", partNumb, " LDiff:", "%2.5f" % auxDiffLuma[x], " LVectD:", "%2.5f" % auxSqrtLuma[x])
      #print(" CuDiff:", "%2.5f" % auxDiffCu[x] , " CuVectD:", "%2.5f" % auxSqrtCu[x])
      #print(" CvDiff:", "%2.5f" % auxDiffCv[x] , " CvVectD:", "%2.5f" % auxSqrtCv[x])
      #print(" TaniL:", "%2.3f" % taniLuma[x] , " TaniCU:", "%2.3f" % taniChromaU[x] , " TaniCV:", "%2.3f" % taniChromaV[x])
      #print(" Sc:", "%5.2f" % (scoreTotal*100.0),"\n")
      
      #if we're nearing the end of the movie, the movies will be smaller and the number of false positives higher
      #with this schema we give less importance to the last "limit" seconds
      #limit = 6
      #scoreTotal = scoreTotal / (1.0+0.1*limit-(auxDiffLuma.size - 1) - x) if ((auxDiffLuma.size - 1) - x) < limit && auxDiffLuma.size > limit

      if scoreTotal >= 0.8 && scoreP != scoreTotal
        print("%5.2f" % (scoreTotal*100.0), "% Hit: Video segment found in #{video} [#{realFrame}~#{realFrame+@@lengthSec}]\n")
        hitCounter += 1
        #print(realFrame, ".", partNumb, " LDiff:", "%2.5f" % auxDiffLuma[x], " LVectD:", "%2.5f" % auxSqrtLuma[x])
        #print(" CuDiff:", "%2.5f" % auxDiffCu[x] , " CuVectD:", "%2.5f" % auxSqrtCu[x])
        #print(" CvDiff:", "%2.5f" % auxDiffCv[x] , " CvVectD:", "%2.5f" % auxSqrtCv[x])
        #print(" TaniL:", "%2.3f" % taniLuma[x] , " TaniCU:", "%2.3f" % taniChromaU[x] , " TaniCV:", "%2.3f" % taniChromaV[x])
        #print(" Sc:", "%5.2f" % (scoreTotal*100.0),"\n")
      end
      
      if debug
        print(realFrame, ".", partNumb, " LDiff:", "%2.5f" % auxDiffLuma[x], " LVectD:", "%2.5f" % auxSqrtLuma[x])
        print(" CuDiff:", "%2.5f" % auxDiffCu[x] , " CuVectD:", "%2.5f" % auxSqrtCu[x])
        print(" CvDiff:", "%2.5f" % auxDiffCv[x] , " CvVectD:", "%2.5f" % auxSqrtCv[x])
        print(" TaniL:", "%2.3f" % taniLuma[x] , " TaniCU:", "%2.3f" % taniChromaU[x] , " TaniCV:", "%2.3f" % taniChromaV[x])
        print(" Sc:", "%5.2f" % (scoreTotal*100.0))
        print("\n")
      end
      
      scoreP = score+scoreTani
      sleep = -1 if (x-sleep) >= 3
      sleepT = -1 if (x-sleepT) >= 3
      
      score = 0.0
      scoreTani = 0.0
      
    end
  end
end

if debug1
	qArray = db.execute( "select * from hashluma where movies > 0" )
	(0..254).each do |e|
		#puts("#{e} #{qArray[e][1].size}") if qArray[e] != nil
		puts("#{e} #{qArray[e][1].to_s.split(',').sort.uniq.size}") if qArray[e] != nil
		puts("#{e} 0") if qArray[e] == nil
	end
end

puts("No hits were found! :(") if hitCounter == 0

print("Database clustering saved an average of ","%5.2f" % (savings/(videoArray.size-1)),"% on Luma", "\n") if sqlite_import
print("Analyzed videos: #{analyzedVideosCounter}\n")
print("Test run-time for #{videoArray.size} movies was ","%5.2f" % (Time.new-stime), " seconds\n")