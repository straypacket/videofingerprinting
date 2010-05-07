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
@@param = 0.0
@@param2 = 0.0
linux = false
sqlite = false
sqlite_import = false

#Path where the videos/logs are
path = 'C:/AviSynthVideos/'

(4..ARGV.size-1).each do |arg|
  
  if ARGV[arg] == "-debug"
    puts("Debug ON")
    debug = true
  elsif ARGV[arg] == "-reverse"
    puts("Reverse ON")
    reverse = true
  elsif ARGV[arg] == "-linux"
    linux = true
    path = '/mnt/AviSynthVideos/'
  elsif ARGV[arg] == "-test"
    @@param = ARGV[arg+1].to_f 
    @@param2 = @@param
  elsif ARGV[arg] == "-test2"
    @@param2 = ARGV[arg+1].to_f 
  elsif ARGV[arg] == "-sqlite"
    puts("SQLite ON")
    sqlite = true
  elsif ARGV[arg] == "-sqlite_import"
    puts("SQLite import ON")
    sqlite_import = true
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

#DFT arrays
#
searchSeqArrayDFT = Array.new
lumaArraySecDFT = Array.new

savings = 0.0

#SQL Info Schema
#
#The integers stored at each second are meabt to be 2 byte long [0-65535]
#   -The first byte is the real part[0-255], the second byte is the decimal part [0-99]. So before inserting:
#     we convert both parts (8 bits) into binary, Ex: Luma = 68.33 = 01000100.00100001
#     join them accordingly (8 bit, 8bit) Ex: 0100010000100001
#     convert back to integer 0100010000100001 = 17441
#     insert 17441 into DB
#   -To retrieve info, do the opposite operation

##SQLite vars
#
if sqlite
  db = SQLite3::Database.new( "test.db" ) if !linux
  db = SQLite3::Database.new( "/home/gsc/test.db" ) if linux
  db = SQLite3::Database.new( "/home/gsc/test_newtable_#{@@param}.db" ) if linux && ( sqlite || sqlite_import )
  #
  begin
    db.execute("create table allmovies (allmovieskey INTEGER PRIMARY KEY,name TEXT,fps double)")
    puts("Creating new allmovies table")
  rescue
    puts("Allmovies table already exists")
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
      lower = array[a].to_f if array[a].to_f < lower
      higher = array[a].to_f if array[a].to_f > higher
    end
  else
    extra = bound-(array.size-1)
    (array.size-1-length*@@part+extra..array.size-1).each do |a|
      lower = array[a].to_f if array[a].to_f < lower
      higher = array[a].to_f if array[a].to_f > higher
    end
  end
  
  aux = 0
  if bound <= array.size-1
    (start..bound).each do |a|
      temp[aux] = (array[a].to_f - lower)/(higher-lower)
      aux += 1
    end
  else
    extra = bound-(array.size-1)
    (array.size-length*@@part+extra..array.size-1).each do |a|
      temp[aux] = (array[a].to_f - lower)/(higher-lower)
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
    lower = array[a].to_f if array[a].to_f < lower
    higher = array[a].to_f if array[a].to_f > higher
  end
  
  aux = 0
  (0..(array.size-1)).each do |a|
    array[aux] = (array[a].to_f - lower)/(higher-lower)
    aux += 1
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
    #therefore, every @@lengthSec*0.5 we also create a new index
    #TODO: play with this 0.5 threshold
    if ((array[c] - array[elem]).abs) > array[c]*param || aux >= @@lengthSec*0.5
      arrayCluster[c] = arrayCluster[c] if aux == 0
      arrayCluster[c] = arrayCluster[c]*1.0/aux if aux > 0
      aux = 0
      c = elem
    end
    arrayCluster[c] = 0 if aux == 0
    arrayCluster[c] += array[elem]
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
    diff += (array1[y].to_f - array2[y].to_f).abs
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

videoArray.each do |video|
  #re-init params
  fps = 0
  lumaArrayFrames = Array.new
  lumaArraySec = Array.new
  chromaUArrayFrames = Array.new
  chromaUArraySec = Array.new
  chromaVArrayFrames = Array.new
  chromaVArraySec = Array.new
  
  #Exception control
  raise RuntimeError, "No log file for #{video}! Did the analysis complete successfuly?" if File.exists?(path + video + ".log2") == false
  
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
  fps = fps.to_i
  
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
  
  ##Database info clustering
  #one DB to rule them all
  c = 0
  aux = 0
  
  if sqlite
    lumaArraySecCluster = arrayCluster(lumaArraySec,@@param)
    
    #we can now insert the shortened hash into a remote DB
    c = nil
    begin
      c = db.execute( "select count(*) from \"#{video}\"" )[0][0].to_i
      raise SQLException if sqlite_import
    rescue
      keys = lumaArraySecCluster.keys.sort
      db.execute("drop table \"#{video}\"") if c != nil
      db.execute("create table \"#{video}\" (s_end int, luma int, chromau int, chromav int)")
      (0..keys.size-2).each do |x| 
        #Convert values to 2-byte integers [0-255].00 * 100 <= 25599 which is lower than 65535 (thanks Christian!)
        avgLuma = (lumaArraySecCluster[keys[x]]*100).to_i
        avgChromaU = (chromaUArraySec[keys[x]]*100).to_i
        avgChromaV = (chromaVArraySec[keys[x]]*100).to_i
        #insert in DB
        db.execute( "insert into \"#{video}\" (s_end,luma,chromau,chromav) values (#{keys[x]},#{avgLuma},#{avgChromaU},#{avgChromaV})")
      end
      #insert last element
      db.execute( "insert into \"#{video}\" (s_end,luma,chromau,chromav) values (#{keys[keys.size-1]},-1,-1,-1)")
    end
  end
  
  savings += (1-((lumaArraySecCluster.size.to_i-1)*1.0/(lumaArraySec.size.to_i-1)*1.0))*100.0

  ##Simulate DB fetch and array reconstruction
  #
  if !sqlite
    chromaUArraySecCluster = arrayCluster(chromaUArraySec,@@param2)
    chromaVArraySecCluster = arrayCluster(chromaVArraySec,@@param2)
    lumaArraySecNew = Array.new
    aux = lumaArraySecCluster.keys.sort
    #p aux
    (0..aux.size-2).each do |x| 
      (aux[x]..(aux[x+1]-1)).each do |y|
        #p "Filling up position #{y} with #{lumaArraySecCluster[aux[x]]} [#{aux[x]}~#{(aux[x+1]-1)}]"
        lumaArraySecNew[y] = lumaArraySecCluster[aux[x]]
      end
    end
    
    chromaUArraySecNew = Array.new
    aux = chromaUArraySecCluster.keys.sort
    #p aux
    (0..aux.size-2).each do |x| 
      (aux[x]..(aux[x+1]-1)).each do |y|
        #p "Filling up position #{y} with #{lumaArraySecCluster[aux[x]]} [#{aux[x]}~#{(aux[x+1]-1)}]"
        chromaUArraySecNew[y] = chromaUArraySecCluster[aux[x]]
      end
    end

    chromaVArraySecNew = Array.new
    aux = chromaVArraySecCluster.keys.sort
    #p aux
    (0..aux.size-2).each do |x| 
      (aux[x]..(aux[x+1]-1)).each do |y|
        #p "Filling up position #{y} with #{lumaArraySecCluster[aux[x]]} [#{aux[x]}~#{(aux[x+1]-1)}]"
        chromaVArraySecNew[y] = chromaVArraySecCluster[aux[x]]
      end
    end
  end

  ## DB fetch and array reconstruction
  #
  if sqlite
    lumaArraySec.clear
    chromaUArraySec.clear
    chromaVArraySec.clear
    #query will be a bi-dimensional array with [row] x [column]
    query = db.execute( "select * from \"#{video}\"" )
    rows = query[0..-1].size
    (0..rows-2).each do |r|
      (query[r][0].to_i..(query[r+1][0].to_i)-1).each do |l|
        lumaArraySec[l] = (query[r][1].to_f)/100.0
        chromaUArraySec[l] = (query[r][2].to_f)/100.0
        chromaVArraySec[l] = (query[r][3].to_f)/100.0
      end
    end
  end
  
  print("Video has a length of #{(lumaArraySec.size-1)/@@part} seconds and each second is divided in #{@@part} parts\n") if debug
  
  ####VIDEO WE WANT TO LOOK FOR (PATTERN TO SEARCH)
  #Populating our Sequence array, this is what we want to find when searching other movies
  #We use the PARTS arrays just created for this, i.e. the *ArraySec[] arrays
  
  #only use source video, passed by ARGV[1]
  if sourceVideo == video
    aux = 0
    sumLuma = sumChromaU = sumChromaV = 0
    print("Using as source video:#{video}\n") if debug
    if (lumaArraySec.size-1)/@@part >= firstSec+@@lengthSec
      ((firstSec*@@part)..((firstSec*@@part)+((@@lengthSec*@@part)-1))).each do |x|
        print("Populating position #{aux} with #{lumaArraySec[x]} [#{firstSec}-#{firstSec+@@lengthSec-1}]\n") if debug
        searchSeqArrayLumaIni[aux] = lumaArraySec[x]
        searchSeqArrayChromaUIni[aux] = chromaUArraySec[x]
        searchSeqArrayChromaVIni[aux] = chromaVArraySec[x]
        sumLuma += searchSeqArrayLumaIni[aux].to_f
        sumChromaU += searchSeqArrayChromaUIni[aux].to_f
        sumChromaV += searchSeqArrayChromaVIni[aux].to_f
        
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
        sumLuma += searchSeqArrayLumaIni[aux].to_f
        sumChromaU += searchSeqArrayChromaUIni[aux].to_f
        sumChromaV += searchSeqArrayChromaVIni[aux].to_f
        
        aux += 1
      end
    end
  
    #Normalize the CLIP array
    norm(searchSeqArrayLumaIni)
    norm(searchSeqArrayChromaUIni)
    norm(searchSeqArrayChromaVIni)
    
    #TODO?
    # Search min and max values
    # Divide clip into smaller 15s clips
    # Normalize each 15s clip
    # Index each 15s clip average and min/max values for upsampling
    
  end
  ####

  print("Search scene [", firstSec ,"-", firstSec+@@lengthSec ,"] has a length of ", searchSeqArrayLumaIni.size," seconds\n") if debug
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
  
  #TODO: fast search (wtf? thought is was here already!)
  
  (0..(lumaArraySec.size - 1)).each do |x|
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
    
    ##normalize the block of the MOVIE we're looking at, until it not exceeds the bounds
    tempArrayLuma = Array.new
    tempArrayChromaU = Array.new
    tempArrayChromaV = Array.new
    
    #If we exceed the end of the array do as if we were within the last bounds of the movie
    #BUT discard the last exceeding number of elements of the array
    bound = (@@lengthSec*@@part)+x-1
    tempArrayLuma = normBound(lumaArraySec,x,bound,@@lengthSec)
    tempArrayChromaU = normBound(chromaUArraySec,x,bound,@@lengthSec)
    tempArrayChromaV = normBound(chromaVArraySec,x,bound,@@lengthSec)
    
    searchSeqArrayLuma = searchSeqArrayLumaIni
    searchSeqArrayChromaU = searchSeqArrayChromaUIni
    searchSeqArrayChromaV = searchSeqArrayChromaVIni
    
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
    taniLuma[x] = tanimoto(searchSeqArrayLuma, tempArrayLuma).to_f
    taniChromaU[x] = tanimoto(searchSeqArrayChromaU, tempArrayChromaU).to_f
    taniChromaV[x] = tanimoto(searchSeqArrayChromaV, tempArrayChromaV).to_f
  
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
  
  #normalize difference between vectors
  norm(auxDiffLuma)
  norm(auxDiffCu)
  norm(auxDiffCv)

  #normalize distance between vectors
  norm(auxSqrtLuma)
  norm(auxSqrtCu)
  norm(auxSqrtCv)
  
  realFrame = -1
  partNumb = 0
  
  maxSize = 1
  sleep = -1
  sleepT = -1
  score = 0.0
  scoreTani = 0.0
  scoreTotal = 0.0
  scoreP = 0.0
  
  taniLumaBuff = Array.new(maxSize,"0".to_f)
  taniCuBuff = Array.new(maxSize,"0".to_f)
  taniCvBuff = Array.new(maxSize,"0".to_f)
  diffLumaBuff = Array.new(maxSize,"1".to_f)
  diffCuBuff = Array.new(maxSize,"1".to_f)
  diffCvBuff = Array.new(maxSize,"1".to_f)
  sqrtLumaBuff = Array.new(maxSize,"1".to_f)
  sqrtCuBuff = Array.new(maxSize,"1".to_f)
  sqrtCvBuff = Array.new(maxSize,"1".to_f)
  
  (0..(auxDiffLuma.size - 1)).each do |x|
    
    partNumb = x%@@part
    realFrame += 1 if partNumb == 0
    
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
    taniThresh = 0.974
    
    ##Scoring
    #
    point = 0.25/6
    
    if diffLumaBuff.sort[0] <= thresh  && sleep == -1
      score += point
    end
    
    if sqrtLumaBuff.sort[0] <= thresh && sleep == -1
      score += point
    end
    
    if diffCuBuff.sort[0] <= thresh && sleep == -1
      score += point
    end
    
    if sqrtCuBuff.sort[0] <= thresh && sleep == -1
      score += point
    end
    
    if diffCvBuff.sort[0] <= thresh && sleep == -1
      score += point
    end
    
    if sqrtCvBuff.sort[0] <= thresh && sleep == -1
      score += point
    end
  
    point = 0.75/3
    
    if  taniLumaBuff.sort[maxSize-1] >= taniThresh && sleepT == -1
      scoreTani += point
    end
    
    if taniCuBuff.sort[maxSize-1] >= taniThresh && sleepT == -1
      scoreTani += point
    end
    
    if taniCvBuff.sort[maxSize-1] >= taniThresh && sleepT == -1
      scoreTani += point
    end
    
    scoreTotal = score+scoreTani
    
    #if we're nearing the end of the movie, the movies will be smaller and the number of false positives higher
    #with this schema we give less importance to the last "limit" seconds
    limit = 6
    scoreTotal = scoreTotal / (1.0+0.1*limit-(auxDiffLuma.size - 1) - x) if ((auxDiffLuma.size - 1) - x) < limit && auxDiffLuma.size > limit

    if scoreTotal >= 0.8 && scoreP != scoreTotal
      print("%5.2f" % (scoreTotal*100.0), "% Hit: Video segment found in #{video} [#{realFrame}~#{realFrame+@@lengthSec}]\n")
      hitCounter += 1
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

puts("No hits were found! :(") if hitCounter == 0

print("Database clustering saved an average of ","%5.2f" % (savings/(videoArray.size-1)),"% on Luma", "\n")
print("Test run-time for #{videoArray.size} movies was ","%5.2f" % (Time.new-stime), " seconds\n")