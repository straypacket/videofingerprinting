#Usage
#avisynthLuma [avg|diff] sourceVideo start length {-debug|-scramble|-subtitle|-reverse|-standalone}

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
scramble = false
subtitle = false
reverse = false
debug = false
standalone = false
param = 0.0
param2 = 0.0
linux = false
sqlite = false
sqlitem = false

#Path where the videos/logs are
path = 'C:/AviSynthVideos/'

(4..ARGV.size-1).each do |arg|
  
  if ARGV[arg] == "-debug"
    puts("Debug ON")
    debug = true
  elsif ARGV[arg] == "-subtitle"
    puts("Subtitle ON")
    subtitle = true
  elsif ARGV[arg] == "-reverse"
    puts("Reverse ON")
    reverse = true
  elsif ARGV[arg] == "-scramble"
    puts("Scramble ON")
    scramble = true
  elsif ARGV[arg] == "-standalone"
    standalone = true
  elsif ARGV[arg] == "-linux"
    linux = true
    path = '/mnt/AviSynthVideos/'
  elsif ARGV[arg] == "-test"
    param = ARGV[arg+1].to_f 
    param2 = param
  elsif ARGV[arg] == "-test2"
    param2 = ARGV[arg+1].to_f 
  elsif ARGV[arg] == "-sqlite"
    puts("SQLite import ON")
    sqlite = true
  elsif ARGV[arg] == "-sqlitem"
    puts("SQLite Multiple DB import ON")
    sqlitem = true
  #else
  #  raise RuntimeError, "Illegal command!"
  end
  
end

puts("Standalone OFF") if standalone == false

#Remaining auxiliary variables
#
method = ARGV[0]
sourceVideo = ARGV[1]
Dir.chdir(path)
videoArray = Array.new
if standalone
  aux = Dir.glob('*.{mp4,wmv}.log2') if !subtitle && !scramble
  aux = Dir.glob('*.{mp4,wmv}.sub.log') if subtitle
  aux = Dir.glob('*.{mp4,wmv}.scramble.log') if scramble
  aux.each do |file|
    filename = file.split(".")[0]+"."+file.split(".")[1]
    videoArray << filename
  end
else
  videoArray = Dir.glob('*.{mp4,wmv}')
end

#for debug (to use while crawler is still running)
#videoArray.sort!
#videoArray.pop

videoArray.reverse! if reverse

#Exception control
raise RuntimeError, "Empty video directory!" if videoArray.empty? && !standalone
raise RuntimeError, "Please use avg or diff as first mandatory argument and the source video as the second argument!\nThe correct command line usage is: avisynthLuma [avg|diff] sourceVideo {-debug|-scramble|-subtitle|-reverse|-standalone}" if ARGV.empty? || ARGV.size < 2

hitCounter = 0

##searchSeqArray operations
#
#firstSec = (15*rand(4))
firstSec = ARGV[2].to_i
lengthSec = ARGV[3].to_i
#these arrays are already the average of each second or part
searchSeqLumaAvg = 0
searchSeqArrayLuma = Array.new
searchSeqArrayLumaIni = Array.new
searchSeqArrayLumaFull = Array.new
searchSeqChromaUAvg = 0
searchSeqArrayChromaU = Array.new
searchSeqArrayChromaUIni = Array.new
searchSeqArrayChromaUFull = Array.new
searchSeqChromaVAvg = 0
searchSeqArrayChromaV = Array.new
searchSeqArrayChromaVIni = Array.new
searchSeqArrayChromaVFull = Array.new
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

#DFT arrays
#
searchSeqArrayDFT = Array.new
lumaArraySecDFT = Array.new

savingsLuma = savingsChromaU = savingsChromaV = 0.0

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
if sqlite || sqlitem
  db = SQLite3::Database.new( "test.db" ) if !linux
  db = SQLite3::Database.new( "/home/gsc/test.db" ) if linux
  db = SQLite3::Database.new( "/home/gsc/test_onetablepermovie_#{param}.db" ) if linux && sqlite
  db = SQLite3::Database.new( "/home/gsc/test_threetablepermovie_#{param}.db" ) if linux && sqlitem
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

#DFT
def dft(inv,array)
  elem = Array.new
  array.each{|e| elem.push( Complex.new(e,0) ) }
  ret=Array.new
  n=elem.size
  a=Math::PI*2.0/n
  a=-a if inv 
  n.times{|i|
    ret[i]=Complex.new(0,0)
    n.times{|j|
      ret[i] = ret[i] + ( elem[j] * Complex.new(Math.cos(a*i*j),-Math.sin(a*i*j)) )
    }
    ret[i] = ret[i] * (1.0/n) if inv
  }
  return ret
end

#Tanimoto Coefficient
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

def float2suj(f)
  avg = f
  avg_int = avg.to_i.to_s(2)
  avg_dec = ((avg-avg.to_i)*100).to_i.to_s(2)
  avg_dec = "0"*(8-avg_dec.size) + avg_dec
  avg_b = avg_int + avg_dec
  avg = avg_b.to_i(2)
  return avg
end

def suj2float(i)
  avg = i
  avg_dec = avg.to_s(2)[-8..-1].to_i(2)/100.0
  avg_int = avg.to_s(2)[0..-9].to_i(2)
  avg = avg_int + avg_dec
  return avg
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

  ####Video analyse
  #
  if standalone
    puts("Standalone mode, the videos will not be analyzed!") if debug
    totalTime = 999999999 if subtitle
  else
    print("====== Analyzing #{video}\n") if debug
    
    #get the correct FPS value with help of FFMpeg
    system "ffmpeg.exe -i #{video} 2> #{video}.ffmpeg"
    line = Array.new
    time = Array.new if scramble
    
    IO.readlines(video+".ffmpeg").each do |out|
      line = out.split if out =~ /Video: /
      time = out.split if out =~ /Duration: / if scramble || subtitle
    end

    #Using FFMpeg's TBN
    fps = line[-2].to_f.round
    if scramble || subtitle
      timeA = time[-6].split(":")
      totalTime = (timeA[2].to_f+(60*timeA[1].to_f)+(60*60*timeA[0].to_f))*fps
    end
    
    #if fps is overly high, assume 29.97 fps
    fps = 29.97 if fps > 100
    print("Detected a video framerate of #{fps}\n") if debug
    
    #delete file
    File.delete(video+".ffmpeg")
    
    #AVISynch output file
    avs = File.open("#{video}.avs", "w")
    savs = File.open("#{video}.scrambled.avs", "w") if scramble
    subavs = File.open("#{video}.sub.avs", "w") if subtitle
    
    #Load the video
    if video =~ /.wmv$/
      avs.puts('DirectShowSource("' + path + video + '", fps = ' + fps.to_s + ' ).ConvertToYV12')
      savs.puts('DirectShowSource("' + path + video + '", fps = ' + fps.to_s + ' ).ConvertToYV12') if scramble
      subavs.puts('DirectShowSource("' + path + video + '", fps = ' + fps.to_s + ' ).ConvertToYV12') if subtitle
    else
      avs.puts('DirectShowSource("' + path + video + '").ConvertToYV12')
      savs.puts('DirectShowSource("' + path + video + '").ConvertToYV12') if scramble
      subavs.puts('DirectShowSource("' + path + video + '").ConvertToYV12') if subtitle
    end
    
    #for testing purposes only. ColorYUV autooptimization to normalize video is better
    avs.puts('ColorYUV(analyze=true,autogain=true)')
    savs.puts('ColorYUV(analyze=true,autogain=true)') if scramble
    subavs.puts('ColorYUV(analyze=true,autogain=true)') if subtitle
    #avs.puts('Greyscale()')
    #savs.puts('Greyscale()') if scramble
    avs.puts('Histogram()')
    savs.puts('Histogram()') if scramble
    subavs.puts('Histogram()') if subtitle
    avs.puts("excessWidth=last.Width%4\nexcessHeight=last.Height%4\nlast.Crop(excessWidth,excessHeight,-0,-0)")
    savs.puts("excessWidth=last.Width%4\nexcessHeight=last.Height%4\nlast.Crop(excessWidth,excessHeight,-0,-0)") if scramble
    subavs.puts("excessWidth=last.Width%4\nexcessHeight=last.Height%4\nlast.Crop(excessWidth,excessHeight,-0,-0)") if subtitle
    avs.puts('Logfile="' + path + video + '.log"')
    savs.puts('Logfile="' + path + video + '.scrambled.log"') if scramble
    subavs.puts('Logfile="' + path + video + '.sub.log"') if subtitle
    
    if scramble
      #cut and "scramble" pieces of length n
      n=lengthSec*fps*2
      options = Array.new
      scramble_ = ""
      (0..(totalTime/n)).each {|e| options << e }
      print("Scrambled #{options.size} pieces in the following order: ") if sourceVideo != video && debug
      while(!options.empty?)
        slot = options.delete_at(rand(100)%options.size-1)
        print("#{slot} ")
        scramble += "Trim(#{(slot*n).to_i},#{(((slot+1)*n).to_i)-1})+"
      end
      print("and the following timings:\n") if sourceVideo != video && debug
      scramble_.chop!
      puts(scramble_) if sourceVideo != video
      savs.puts(scramble_)
    end
    
    subavs.puts("Subtitle(\"Some random text \n with multiple lines \n to confuse people\",-1,-1,0,#{totalTime.to_int},\"Arial\",28,$FFFFFF)") if subtitle
    
    avs.puts('WriteFile(Logfile, "current_frame", """ ";" """,""" time("%H:%M:%S") """, """ ";" """, "AverageLuma" , """ ";" """, "YDifferenceFromPrevious" , """ ";" """, "AverageChromaU" , """ ";" """, "AverageChromaV")')
    savs.puts('WriteFile(Logfile, "current_frame", """ ";" """,""" time("%H:%M:%S") """, """ ";" """, "AverageLuma" , """ ";" """, "YDifferenceFromPrevious" , """ ";" """, "AverageChromaU" , """ ";" """, "AverageChromaV")') if scramble
    subavs.puts('WriteFile(Logfile, "current_frame", """ ";" """,""" time("%H:%M:%S") """, """ ";" """, "AverageLuma" , """ ";" """, "YDifferenceFromPrevious" , """ ";" """, "AverageChromaU" , """ ";" """, "AverageChromaV")') if subtitle
    #and we wrap it up ;)
    avs.close
    savs.close if scramble
    subavs.close if subtitle
    
    #Execute avsutil with our script
    #clean up old files
    #File.delete(path + video + ".log") if File.exist?(path + video + ".log") && !scramble && !subtitle
    #File.delete(path + video + ".scrambled.log") if File.exist?(path + video + ".scrambled.log") && scramble
    #File.delete(path + video + ".sub.log") if File.exist?(path + video + ".sub.log") && subtitle
    #exec/system
    if scramble
      system "C:/AviSynthVideos/avsutil.exe", video+".avs", "play" if sourceVideo == video && !File.exist?(path + video + ".log")
      system "C:/AviSynthVideos/avsutil.exe", video+".scrambled.avs", "play" if sourceVideo != video && !File.exist?(path + video + ".scrambled.log")
    end
    
    if subtitle
      system "C:/AviSynthVideos/avsutil.exe", video+".avs", "play" if sourceVideo == video && !File.exist?(path + video + ".log")
      system "C:/AviSynthVideos/avsutil.exe", video+".sub.avs", "play" if sourceVideo != video && !File.exist?(path + video + ".sub.log")
    end
    
    if !scramble && !subtitle
      system "C:/AviSynthVideos/avsutil.exe", video+".avs", "play" if !File.exist?(path + video + ".log")
    end
    
  end
  #
  ##end video analyse
  
  #Add fps at the end of log
  if !standalone
    if scramble
      puts("Adding \"fps #{fps}\" at the end of file log #{path}#{video}.log") if sourceVideo == video && debug
      file = File.open(path + video + ".log", "a") if sourceVideo == video
      puts("Adding \"fps #{fps}\" at the end of file log #{path}#{video}.scramble.log") if sourceVideo != video && debug
      file = File.open(path + video + ".scramble.log", "a") if sourceVideo != video
      file.write("fps #{fps}\n")
      file.close
    elsif subtitle
      puts("Adding \"fps #{fps}\" at the end of file log #{path}#{video}.log") if sourceVideo == video && debug
      file = File.open(path + video + ".log", "a") if sourceVideo == video
      puts("Adding \"fps #{fps}\" at the end of file log #{path}#{video}.sub.log") if sourceVideo != video && debug
      file = File.open(path + video + ".sub.log", "a") if sourceVideo != video
      file.write("fps #{fps}\n")
      file.close
    else
      puts("Adding \"fps #{fps}\" at the end of file log #{path}#{video}.log") if debug
      file = File.open(path + video + ".log", "a")
      file.write("fps #{fps}\n")
      file.close
    end
  end
  
  
  #Exception control
  if scramble
    raise RuntimeError, "No log file! Did avsutil.exe complete successfuly?" if File.exists?(path + video + ".log") == false && sourceVideo == video
    raise RuntimeError, "No log file! Did avsutil.exe complete successfuly?" if File.exists?(path + video + ".scrambled.log") == false && sourceVideo != video
  elsif subtitle
    raise RuntimeError, "No log file! Did avsutil.exe complete successfuly?" if File.exists?(path + video + ".log") == false && sourceVideo == video
    raise RuntimeError, "No log file! Did avsutil.exe complete successfuly?" if File.exists?(path + video + ".sub.log") == false && sourceVideo != video
  else
    raise RuntimeError, "No log file! Did avsutil.exe complete successfuly?" if File.exists?(path + video + ".log2") == false
  end
  
  #Extract the results
  if scramble
    log = File.open(path + video + ".log","r") if sourceVideo == video
    puts("Reading #{video}.log") if sourceVideo == video && debug
    log = File.open(path + video + ".scrambled.log","r") if sourceVideo != video
    puts("Reading #{video}.scrambled.log") if sourceVideo != video && debug
  elsif subtitle
    log = File.open(path + video + ".log","r") if sourceVideo == video
    puts("Reading #{video}.log") if sourceVideo == video && debug
    log = File.open(path + video + ".sub.log","r") if sourceVideo != video
    puts("Reading #{video}.sub.log") if sourceVideo != video && debug
  else
    log = File.open(path + video + ".log2","r")
    puts("Reading #{video}.log2") if debug
  end
  
  log.each do |line|
    if line =~ /^fps/ && standalone
      fps = line.split(" ")[1].to_f
      raise RuntimeError, "Wrong FPS value for file #{video}" if fps.nan?
      fps = fps.to_i
      puts("Reading FPS off log file (#{fps})") if debug
    else
      aux = line.split(";")
      lumaArrayFrames[aux[0].to_i] = "%3.2f"%aux[2] if method == "avg"
      lumaArrayFrames[aux[0].to_i] = "%3.2f"%aux[3] if method == "diff"
      chromaUArrayFrames[aux[0].to_i] = "%3.2f"%aux[4]
      chromaVArrayFrames[aux[0].to_i] = "%3.2f"%aux[5]
      #lumaArrayFrames[aux[0].to_i] = aux[2] if method == "avg"
      #lumaArrayFrames[aux[0].to_i] = aux[3] if method == "diff"
      #chromaUArrayFrames[aux[0].to_i] = aux[4]
      #chromaVArrayFrames[aux[0].to_i] = aux[5]
    end
  end
  log.close
  
  raise RuntimeError, "Wrong FPS value for file #{video}" if fps == 0.0
  fps = fps.to_i
  
  #### This will be the huge MOVIE we want to compare to 
  #Partition variable for seconds
  part = 1
  ##populate the average PART arrays *ArraySec[]
  print("Movie #{video} has ", (lumaArrayFrames.size-1)/(fps*part), " parts and each part is divided into ", (fps/part).to_int, " frames\n") if debug
  (0..((lumaArrayFrames.size-1)/(fps*part)-1)).each do |p| #  number of parts per movie
    avgLuma = avgChromaU = avgChromaV = 0.0
    (0..(fps/part)-1).each do |f| #  # of frames per part
      avgLuma += lumaArrayFrames[((fps/part)*p)+f].to_f
      avgChromaU += chromaUArrayFrames[((fps/part)*p)+f].to_f
      avgChromaV += chromaVArrayFrames[((fps/part)*p)+f].to_f
    end
    
    #average the values
    lumaArraySec[p] = ("%3.2f"%(avgLuma/fps*part)).to_f
    chromaUArraySec[p] = ("%3.2f"%(avgChromaU/fps*part)).to_f
    chromaVArraySec[p] = ("%3.2f"%(avgChromaV/fps*part)).to_f
    
  end
  
  ##Database info clustering experiment
  #one DB to rule them all
  lumaArraySecCluster = Hash.new()
  chromaUArraySecCluster = Hash.new()
  chromaVArraySecCluster = Hash.new()
  c = 0
  aux = 0
  
  if !sqlitem && sqlite
    (0..lumaArraySec.size-2).each do |elem|
      lumaArraySecCluster[c] = 0 if aux == 0
      chromaUArraySecCluster[c] = 0 if aux == 0
      chromaVArraySecCluster[c] = 0 if aux == 0
      #if we're looking for a piece in the DB where lengthSec has no min/max normalization gives problems.
      #therefore, every lengthSec*0.5 we also create a new index
      if ((lumaArraySec[c] - lumaArraySec[elem]).abs > lumaArraySec[c]*param) || ((chromaUArraySec[c] - chromaUArraySec[elem]).abs > chromaUArraySec[c]*param2) || ((chromaVArraySec[c] - chromaVArraySec[elem]).abs > chromaVArraySec[c]*param2) || aux >= lengthSec*0.5
        lumaArraySecCluster[c] = lumaArraySecCluster[c] if aux == 0
        chromaUArraySecCluster[c] = chromaUArraySecCluster[c] if aux == 0
        chromaVArraySecCluster[c] = chromaVArraySecCluster[c] if aux == 0
        lumaArraySecCluster[c] = lumaArraySecCluster[c]*1.0/aux if aux > 0
        chromaUArraySecCluster[c] = chromaUArraySecCluster[c]*1.0/aux if aux > 0
        chromaVArraySecCluster[c] = chromaVArraySecCluster[c]*1.0/aux if aux > 0
        aux = 0
        c = elem
      end
      lumaArraySecCluster[c] = 0 if aux == 0
      chromaUArraySecCluster[c] = 0 if aux == 0
      chromaVArraySecCluster[c] = 0 if aux == 0
      lumaArraySecCluster[c] += lumaArraySec[elem]
      chromaUArraySecCluster[c] += chromaUArraySec[elem]
      chromaVArraySecCluster[c] += chromaVArraySec[elem]
      aux += 1
    end
    lumaArraySecCluster[c] = lumaArraySecCluster[c] if aux == 0
    chromaUArraySecCluster[c] = chromaUArraySecCluster[c] if aux == 0
    chromaVArraySecCluster[c] = chromaVArraySecCluster[c] if aux == 0
    lumaArraySecCluster[c] = lumaArraySecCluster[c]*1.0/aux if aux > 0
    chromaUArraySecCluster[c] = chromaUArraySecCluster[c]*1.0/aux if aux > 0
    chromaVArraySecCluster[c] = chromaVArraySecCluster[c]*1.0/aux if aux > 0
    #add last elem
    lumaArraySecCluster[lumaArraySec.size-1] = -1
    chromaUArraySecCluster[chromaUArraySec.size-1] = -1
    chromaVArraySecCluster[chromaUArraySec.size-1] = -1
  end

  ##Database info clustering experiment
  #multiple DBs
  if sqlitem
    lumaArraySecCluster = Hash.new()
    c = 0
    aux = 0
    (0..lumaArraySec.size-2).each do |elem|
      lumaArraySecCluster[c] = 0 if aux == 0
      #if we're looking for a piece in the DB where lengthSec has no min/max normalization gives problems.
      #therefore, every lengthSec*0.5 we also create a new index
      if ((lumaArraySec[c] - lumaArraySec[elem]).abs > lumaArraySec[c]*param) || aux >= lengthSec*0.5
        #p "cluster begin #{elem}"
        lumaArraySecCluster[c] = lumaArraySecCluster[c] if aux == 0
        lumaArraySecCluster[c] = lumaArraySecCluster[c]*1.0/aux if aux > 0
        aux = 0
        c = elem
      end
      lumaArraySecCluster[c] = 0 if aux == 0
      lumaArraySecCluster[c] += lumaArraySec[elem]
      aux += 1
    end
    lumaArraySecCluster[c] = lumaArraySecCluster[c] if aux == 0
    lumaArraySecCluster[c] = lumaArraySecCluster[c]*1.0/aux if aux > 0
    #add last elem
    lumaArraySecCluster[lumaArraySec.size-1] = -1
    
    chromaUArraySecCluster = Hash.new()
    c = 0
    aux = 0
    (0..chromaUArraySec.size-2).each do |elem|
      chromaUArraySecCluster[c] = 0 if aux == 0
      #if we're looking for a piece in the DB where lengthSec has no min/max, normalization gives problems.
      #therefore, every lengthSec*0.5 we also create a new index
      if ((chromaUArraySec[c] - chromaUArraySec[elem]).abs > chromaUArraySec[c]*param2) || aux >= lengthSec*0.5
        #p "cluster begin #{elem}"
        chromaUArraySecCluster[c] = chromaUArraySecCluster[c] if aux == 0
        chromaUArraySecCluster[c] = chromaUArraySecCluster[c]*1.0/aux if aux > 0
        aux = 0
        c = elem
      end
      chromaUArraySecCluster[c] = 0 if aux == 0
      chromaUArraySecCluster[c] += chromaUArraySec[elem]
      aux += 1
    end
    chromaUArraySecCluster[c] = chromaUArraySecCluster[c] if aux == 0
    chromaUArraySecCluster[c] = chromaUArraySecCluster[c]*1.0/aux if aux > 0
    #add last elem
    chromaUArraySecCluster[chromaUArraySec.size-1] = -1
    
    chromaVArraySecCluster = Hash.new()
    c = 0
    aux = 0
    (0..chromaVArraySec.size-2).each do |elem|
      chromaVArraySecCluster[c] = 0 if aux == 0
      #if we're looking for a piece in the DB where lengthSec has no min/max, normalization gives problems.
      #therefore, every lengthSec*0.5 we also create a new index
      if ((chromaVArraySec[c] - chromaVArraySec[elem]).abs > chromaVArraySec[c]*param2) || aux >= lengthSec*0.5
        #p "cluster begin #{elem}"
        chromaVArraySecCluster[c] = chromaVArraySecCluster[c] if aux == 0
        chromaVArraySecCluster[c] = chromaVArraySecCluster[c]*1.0/aux if aux > 0
        aux = 0
        c = elem
      end
      chromaVArraySecCluster[c] = 0 if aux == 0
      chromaVArraySecCluster[c] += chromaVArraySec[elem]
      aux += 1
    end
    chromaVArraySecCluster[c] = chromaVArraySecCluster[c] if aux == 0
    chromaVArraySecCluster[c] = chromaVArraySecCluster[c]*1.0/aux if aux > 0
    #add last elem
    chromaVArraySecCluster[chromaVArraySec.size-1] = -1
  end
  
  #p lumaArraySec
  #p lumaArraySecCluster
  
  #we can now insert the shortened hash into a remote DB
  if sqlite
    keys = lumaArraySecCluster.keys.sort
    c = nil
    begin
      c = db.execute( "select count(*) from \"#{video}\"" )[0][0].to_i
      #if the information we have stored in the DB is somewhat incorrect, raise an exception and reconstruct the table
      #if c != lumaArraySecCluster.size
      #  puts("Recontructing table for movie #{video} (#{c} vs #{lumaArraySecCluster.size})")
      #  raise SQLException
      #end
    rescue
      #puts("Rescue!")
      db.execute("drop table \"#{video}\"") if c != nil
      db.execute("create table \"#{video}\" (s_end int, luma int, chromau int, chromav int)")
      (0..keys.size-2).each do |x| 
        #Convert values to out format (suj)
        avgLuma = float2suj(lumaArraySecCluster[keys[x]])
        avgChromaU = float2suj(chromaUArraySecCluster[keys[x]])
        avgChromaV = float2suj(chromaVArraySecCluster[keys[x]])
        #insert in DB
        db.execute( "insert into \"#{video}\" (s_end,luma,chromau,chromav) values (#{keys[x]},#{avgLuma},#{avgChromaU},#{avgChromaV})")
      end
      #insert last element
      db.execute( "insert into \"#{video}\" (s_end,luma,chromau,chromav) values (#{keys[keys.size-1]},-1,-1,-1)")
    end
  end
  
  if sqlitem
    keys = lumaArraySecCluster.keys.sort
    c = nil
    begin
      c = db.execute( "select count(*) from \"#{video}_l\"" )[0][0].to_i
      #if the information we have stored in the DB is somewhat incorrect, raise an exception and reconstruct the table
      #if c != lumaArraySecCluster.size
      #  #puts("Recontructing Luma table for movie #{video} (#{c} vs #{lumaArraySecCluster.size}")
      #  raise SQLException
      #end
    rescue
      db.execute("drop table \"#{video}_l\"") if c != nil
      db.execute("create table \"#{video}_l\" (s_end int, luma int)")
      (0..keys.size-2).each do |x| 
        #Convert values to out format (suj)
        avgLuma = float2suj(lumaArraySecCluster[keys[x]])
        #insert in DB
        db.execute( "insert into \"#{video}_l\" (s_end,luma) values (#{keys[x]},#{avgLuma})")
      end
      #insert last element
      db.execute( "insert into \"#{video}_l\" (s_end,luma) values (#{keys[keys.size-1]},-1)")
    end

    keys = chromaUArraySecCluster.keys.sort
    c = nil
    begin
      c = db.execute( "select count(*) from \"#{video}_cu\"" )[0][0].to_i
      #if the information we have stored in the DB is somewhat incorrect, raise an exception and reconstruct the table
      #if c != chromaUArraySecCluster.size
      #  #puts("Recontructing ChromaU table for movie #{video} (#{c} vs #{chromaUArraySecCluster.size}")
      #  raise SQLException
      #end
    rescue
      db.execute("drop table \"#{video}_cu\"") if c != nil
      db.execute("create table \"#{video}_cu\" (s_end int, chromau int)")
      (0..keys.size-2).each do |x| 
        #Convert values to out format (suj)
        avgChromaU = float2suj(chromaUArraySecCluster[keys[x]])
        #insert in DB
        db.execute( "insert into \"#{video}_cu\" (s_end,chromau) values (#{keys[x]},#{avgChromaU})")
      end
      #insert last element
      db.execute( "insert into \"#{video}_cu\" (s_end,chromau) values (#{keys[keys.size-1]},-1)")
    end
    
    keys = chromaVArraySecCluster.keys.sort
    c = nil
    begin
      c = db.execute( "select count(*) from \"#{video}_cv\"" )[0][0].to_i
      #if the information we have stored in the DB is somewhat incorrect, raise an exception and reconstruct the table
      #if c != chromaVArraySecCluster.size
      #  #puts("Recontructing ChromaV table for movie #{video} (#{c} vs #{chromaVArraySecCluster.size}")
      #  raise SQLException
      #end
    rescue
      db.execute("drop table \"#{video}_cv\"") if c != nil
      db.execute("create table \"#{video}_cv\" (s_end int, chromav int)")
      (0..keys.size-2).each do |x| 
        #Convert values to out format (suj)
        avgChromaV = float2suj(chromaVArraySecCluster[keys[x]])
        #insert in DB
        db.execute( "insert into \"#{video}_cv\" (s_end,chromav) values (#{keys[x]},#{avgChromaV})")
      end
      #insert last element
      db.execute( "insert into \"#{video}_cv\" (s_end,chromav) values (#{keys[keys.size-1]},-1)")
    end

  end
  
  savingsLuma += (1-((lumaArraySecCluster.size-1)*1.0/(lumaArraySec.size-1)))*100
  savingsChromaU += (1-((chromaUArraySecCluster.size-1)*1.0/(chromaUArraySec.size-1)))*100
  savingsChromaV += (1-((chromaVArraySecCluster.size-1)*1.0/(chromaVArraySec.size-1)))*100
  #print "and #{c} clusters, saving ", "%5.2f"%savings, " % of space\n"

  ##Simulate DB fetch and array reconstruction
  #
  if !sqlite
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
    lumaArraySecNew = Array.new
    chromaUArraySecNew = Array.new
    chromaVArraySecNew = Array.new
    #query will be a bi-dimensional array with [row] x [column]
    query = db.execute( "select * from \"#{video}\"" )
    rows = query[0..-1].size
    (0..rows-2).each do |r|
      (query[r][0].to_i..(query[r+1][0].to_i)-1).each do |l|
        lumaArraySecNew[l] = suj2float(query[r][1].to_i)
        chromaUArraySecNew[l] = suj2float(query[r][2].to_i)
        chromaVArraySecNew[l] = suj2float(query[r][3].to_i)
      end
    end
    #print("#{query[rows-1][0]} #{query[rows-2][1]} #{query[rows-2][2]} #{query[rows-2][3]}\n")
  end
  
  if sqlitem
    lumaArraySecNew = Array.new
    chromaUArraySecNew = Array.new
    chromaVArraySecNew = Array.new
    #query will be a bi-dimensional array with [row] x [column]
    query = db.execute( "select * from \"#{video}_l\"" )
    rows = query[0..-1].size
    (0..rows-2).each do |r|
      (query[r][0].to_i..(query[r+1][0].to_i)-1).each do |l|
        lumaArraySecNew[l] = suj2float(query[r][1].to_i)
      end
    end
    
    query = db.execute( "select * from \"#{video}_cu\"" )
    rows = query[0..-1].size
    (0..rows-2).each do |r|
      (query[r][0].to_i..(query[r+1][0].to_i)-1).each do |l|
        chromaUArraySecNew[l] = suj2float(query[r][1].to_i)
      end
    end
    
    query = db.execute( "select * from \"#{video}_cv\"" )
    rows = query[0..-1].size
    (0..rows-2).each do |r|
      (query[r][0].to_i..(query[r+1][0].to_i)-1).each do |l|
        chromaVArraySecNew[l] = suj2float(query[r][1].to_i)
      end
    end
    #print("#{query[rows-1][0]} #{query[rows-2][1]} #{query[rows-2][2]} #{query[rows-2][3]}\n")
  end

  #p lumaArraySec
  #p lumaArraySecNew
  
  #p lumaArraySec.size
  #p lumaArraySecNew.size
  
  lumaArraySec = lumaArraySecNew
  chromaUArraySec = chromaUArraySecNew
  chromaVArraySec = chromaVArraySecNew
  
  #puts("WARNING! The video you're looking at is too short for the chosen time slot search!\nLooking for [#{firstSec}~#{firstSec+lengthSec}] in #{video} movie which has size of [0~#{lumaArraySec.size-1}]") if (lumaArraySec.size-1)/part < firstSec+lengthSec
  #print("Video has a length of #{(lumaArraySec.size-1)/part} seconds and each second is divided in #{part} parts\n") if debug
  
  ####VIDEO WE WANT TO LOOK FOR (PATTERN TO SEARCH)
  #Populating our Sequence array, this is what we want to find when searching other movies
  #We use the PARTS arrays just created for this, i.e. the *ArraySec[] arrays

  lowerLuma = 1000000
  lowerChromaU = 1000000
  lowerChromaV = 1000000
  higherLuma = 0
  higherChromaU = 0
  higherChromaV = 0
  
  #only use source video, passed by ARGV[1]
  if sourceVideo == video
    aux = 0
    sumLuma = sumChromaU = sumChromaV = 0
    print("Using as source video:#{video}\n") if debug
    if (lumaArraySec.size-1)/part >= firstSec+lengthSec
      ((firstSec*part)..((firstSec*part)+((lengthSec*part)-1))).each do |x|
        print("Populating position #{aux} with #{lumaArraySec[x]} [#{firstSec}-#{firstSec+lengthSec-1}]\n") if debug
        searchSeqArrayLumaIni[aux] = lumaArraySec[x]
        searchSeqArrayChromaUIni[aux] = chromaUArraySec[x]
        searchSeqArrayChromaVIni[aux] = chromaVArraySec[x]
        sumLuma += searchSeqArrayLumaIni[aux].to_f
        sumChromaU += searchSeqArrayChromaUIni[aux].to_f
        sumChromaV += searchSeqArrayChromaVIni[aux].to_f
     
        #grab max and min values for future normalization
        lowerLuma = searchSeqArrayLumaIni[aux].to_f if searchSeqArrayLumaIni[aux].to_f < lowerLuma
        higherLuma = searchSeqArrayLumaIni[aux].to_f if searchSeqArrayLumaIni[aux].to_f > higherLuma
        lowerChromaU = searchSeqArrayChromaUIni[aux].to_f if searchSeqArrayChromaUIni[aux].to_f < lowerChromaU
        higherChromaU = searchSeqArrayChromaUIni[aux].to_f if searchSeqArrayChromaUIni[aux].to_f > higherChromaU
        lowerChromaV = searchSeqArrayChromaVIni[aux].to_f if searchSeqArrayChromaVIni[aux].to_f < lowerChromaV
        higherChromaV = searchSeqArrayChromaVIni[aux].to_f if searchSeqArrayChromaVIni[aux].to_f > higherChromaV
        
        aux += 1
      end
    else
      puts("WARNING! The video you're looking at is too short for the chosen time slot search!\nLooking for [#{firstSec}~#{firstSec+lengthSec}] in #{video} movie which has a size of [0~#{lumaArraySec.size-1}].") if (lumaArraySec.size-1)/part < firstSec+lengthSec
      print("Video has a length of #{(lumaArraySec.size-1)/part} seconds and each second is divided in #{part} parts\n") if debug
      raise RuntimeError, "Video #{video} has no such segment [#{firstSec}~#{firstSec+lengthSec}] or is too small (#{lumaArraySec.size-1-firstSec})" if (lumaArraySec.size-1-firstSec < 3)
      puts("Using #{video}:[#{firstSec}~#{lumaArraySec.size-1}] instead (#{lumaArraySec.size-1-firstSec} secs).")
      lengthSec = lumaArraySec.size-1-firstSec
      ((firstSec*part)..((firstSec*part)+((lengthSec*part)-1))).each do |x|
        print("Populating position #{aux} with #{lumaArraySec[x]} [#{firstSec}-#{firstSec+lengthSec-1}]\n") if debug
        searchSeqArrayLumaIni[aux] = lumaArraySec[x]
        searchSeqArrayChromaUIni[aux] = chromaUArraySec[x]
        searchSeqArrayChromaVIni[aux] = chromaVArraySec[x]
        sumLuma += searchSeqArrayLumaIni[aux].to_f
        sumChromaU += searchSeqArrayChromaUIni[aux].to_f
        sumChromaV += searchSeqArrayChromaVIni[aux].to_f
     
        #grab max and min values for future normalization
        lowerLuma = searchSeqArrayLumaIni[aux].to_f if searchSeqArrayLumaIni[aux].to_f < lowerLuma
        higherLuma = searchSeqArrayLumaIni[aux].to_f if searchSeqArrayLumaIni[aux].to_f > higherLuma
        lowerChromaU = searchSeqArrayChromaUIni[aux].to_f if searchSeqArrayChromaUIni[aux].to_f < lowerChromaU
        higherChromaU = searchSeqArrayChromaUIni[aux].to_f if searchSeqArrayChromaUIni[aux].to_f > higherChromaU
        lowerChromaV = searchSeqArrayChromaVIni[aux].to_f if searchSeqArrayChromaVIni[aux].to_f < lowerChromaV
        higherChromaV = searchSeqArrayChromaVIni[aux].to_f if searchSeqArrayChromaVIni[aux].to_f > higherChromaV
        
        aux += 1
      end
    end
    
    print("Limit values found for Luma:#{lowerLuma}~#{higherLuma}, ChromaU:#{lowerChromaU}~#{higherChromaU}, ChromaV:#{lowerChromaV}~#{higherChromaV} ... normalizing ... ") if debug
  
    #Normalize the CLIP array
    (0..(searchSeqArrayLumaIni.size-1)).each do |aux|
      searchSeqArrayLumaIni[aux] = (searchSeqArrayLumaIni[aux].to_f - lowerLuma)/(higherLuma-lowerLuma) if higherLuma != lowerLuma
      searchSeqArrayChromaUIni[aux] = (searchSeqArrayChromaUIni[aux].to_f - lowerChromaU)/(higherChromaU-lowerChromaU) if higherChromaU != lowerChromaU
      searchSeqArrayChromaVIni[aux] = (searchSeqArrayChromaVIni[aux].to_f - lowerChromaV)/(higherChromaV-lowerChromaV) if higherChromaV != lowerChromaV
    end
    
    #Average the sums of the CLIP
    searchSeqLumaAvgIni = sumLuma / (lengthSec*part)
    searchSeqChromaUAvgIni = sumChromaU / (lengthSec*part)
    searchSeqChromaVAvgIni = sumChromaV / (lengthSec*part)
    
    # Search min and max values
    # Divide clip into smaller 15s clips
    # Normalize each 15s clip
    # Index each 15s clip average and min/max values for upsampling
    
  end
  ####
  
  ## Testing, empty the clip arrays
  #searchSeqArrayLuma = Array.new(searchSeqArrayLuma.size, 0)
  #searchSeqArrayChromaU = Array.new(searchSeqArrayChromaU.size, 0)
  #searchSeqArrayChromaV = Array.new(searchSeqArrayChromaV.size, 0)

  print("Search scene [", firstSec ,"-", firstSec+lengthSec ,"] has a length of ", searchSeqArrayLumaIni.size," seconds\n") if debug
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
  lowerLuma = 1000000
  lowerChromaU = 1000000
  lowerChromaV = 1000000
  higherLuma = 0
  higherChromaU = 0
  higherChromaV = 0
  lowerDiffLuma = 1000000
  lowerDiffChromaU = 1000000
  lowerDiffChromaV = 1000000
  higherDiffLuma = 0
  higherDiffChromaU = 0
  higherDiffChromaV = 0  
  lowerSqrtLuma = 1000000
  lowerSqrtChromaU = 1000000
  lowerSqrtChromaV = 1000000
  higherSqrtLuma = 0
  higherSqrtChromaU = 0
  higherSqrtChromaV = 0
  
  #now that we have searchSeqArray[] and lumaArraySec[], bruteforce the whole movie to find our sequence, using seconds
  #we start at second 0 and compare every second of our searchSeqArray[] movie to the one of the lumaArraySec[] clip, sequentially
  #then proceed to frame 1, then frame 2, etc, etc
  
  (0..(lumaArraySec.size - 1)).each do |x|
    diffLuma = diffChromaU = diffChromaV = 0.0
    similarLumaAvg = similarChromaUAvg = similarChromaVAvg = 0.0
    diffLumaAvg = Array.new
    diffChromaVAvg = Array.new
    diffChromaUAvg = Array.new
    distLuma = Array.new
    distChromaU = Array.new
    distChromaV = Array.new
    
    partNumb = x%part
    realFrame += 1 if partNumb == 0
  
    
    ##normalize the block of the MOVIE we're looking at, until it not exceeds the bounds
    tempArrayLuma = Array.new
    tempArrayChromaU = Array.new
    tempArrayChromaV = Array.new
    
    #If we exceed the end of the array do as if we were within the last bounds of the movie
    #BUT discard the last exceeding #bound number of elements of the array
    bound = (lengthSec*part)+x-1
    if bound <= lumaArraySec.size-1
      (x..bound).each do |a|
        lowerLuma = lumaArraySec[a].to_f if lumaArraySec[a].to_f < lowerLuma
        higherLuma = lumaArraySec[a].to_f if lumaArraySec[a].to_f > higherLuma
        lowerChromaU = chromaUArraySec[a].to_f if chromaUArraySec[a].to_f < lowerChromaU
        higherChromaU = chromaUArraySec[a].to_f if chromaUArraySec[a].to_f > higherChromaU
        lowerChromaV = chromaVArraySec[a].to_f if chromaVArraySec[a].to_f < lowerChromaV
        higherChromaV = chromaVArraySec[a].to_f if chromaVArraySec[a].to_f > higherChromaV
      end
    else
      extra = bound-(lumaArraySec.size-1)
      (lumaArraySec.size-1-lengthSec*part+extra..lumaArraySec.size-1).each do |a|
        lowerLuma = lumaArraySec[a].to_f if lumaArraySec[a].to_f < lowerLuma
        higherLuma = lumaArraySec[a].to_f if lumaArraySec[a].to_f > higherLuma
        lowerChromaU = chromaUArraySec[a].to_f if chromaUArraySec[a].to_f < lowerChromaU
        higherChromaU = chromaUArraySec[a].to_f if chromaUArraySec[a].to_f > higherChromaU
        lowerChromaV = chromaVArraySec[a].to_f if chromaVArraySec[a].to_f < lowerChromaV
        higherChromaV = chromaVArraySec[a].to_f if chromaVArraySec[a].to_f > higherChromaV
      end
    end
    
    aux = 0
    if bound <= lumaArraySec.size-1
      (x..bound).each do |a|
        tempArrayLuma[aux] = (lumaArraySec[a].to_f - lowerLuma)/(higherLuma-lowerLuma)
        tempArrayChromaU[aux] = (chromaUArraySec[a].to_f - lowerChromaU)/(higherChromaU-lowerChromaU)
        tempArrayChromaV[aux] = (chromaVArraySec[a].to_f - lowerChromaV)/(higherChromaV-lowerChromaV)
        aux += 1
      end
    else
      extra = bound-(lumaArraySec.size-1)
      (lumaArraySec.size-lengthSec*part+extra..lumaArraySec.size-1).each do |a|
        tempArrayLuma[aux] = (lumaArraySec[a].to_f - lowerLuma)/(higherLuma-lowerLuma)
        tempArrayChromaU[aux] = (chromaUArraySec[a].to_f - lowerChromaU)/(higherChromaU-lowerChromaU)
        tempArrayChromaV[aux] = (chromaVArraySec[a].to_f - lowerChromaV)/(higherChromaV-lowerChromaV)
        aux += 1
      end
    end
    
    lowerLuma = 1000000
    higherLuma = 0
    lowerChromaU = 1000000
    higherChromaU = 0
    lowerChromaV = 1000000
    higherChromaV = 0
    ##
    
    searchSeqArrayLuma = searchSeqArrayLumaIni[0..(searchSeqArrayLumaIni.size-1)]
    searchSeqArrayChromaU = searchSeqArrayChromaUIni[0..(searchSeqArrayLumaIni.size-1)]
    searchSeqArrayChromaV = searchSeqArrayChromaVIni[0..(searchSeqArrayLumaIni.size-1)]
    
    #When reaching the end of the array, we had a condition where the values outside of the array would be compared
    #Ex: Searching for 10 second blocks in a 60 second movie, would give us a search between [55-65]. 
    #Also, we don't want to compare only 1 second (too many false positives). 5 seconds is the lowest piece we search.
    if ( lumaArraySec.size-x < lengthSec*part )
      bound = lumaArraySec.size-x-1
      #bound = 5 if lumaArraySec.size-x < 5
      searchSeqArrayLuma = searchSeqArrayLumaIni[0..bound]
      searchSeqArrayChromaU = searchSeqArrayChromaUIni[0..bound]
      searchSeqArrayChromaV = searchSeqArrayChromaVIni[0..bound]
    end
    
    ##ALGORITHMS
    #
    
    ##tanimoto
    #
    taniLuma[x] = tanimoto(searchSeqArrayLuma, tempArrayLuma).to_f
    taniChromaU[x] = tanimoto(searchSeqArrayChromaU, tempArrayChromaU).to_f
    taniChromaV[x] = tanimoto(searchSeqArrayChromaV, tempArrayChromaV).to_f
  
    ##Difference between CLIP and MOVIE
    #
    (0..(searchSeqArrayLuma.size-1)).each do |y|
      diffLuma += (searchSeqArrayLuma[y].to_f - tempArrayLuma[y].to_f).abs
      diffChromaU += (searchSeqArrayChromaU[y].to_f - tempArrayChromaU[y].to_f).abs
      diffChromaV += (searchSeqArrayChromaV[y].to_f - tempArrayChromaV[y].to_f).abs
    end
    diffLumaAvg = diffLuma / (searchSeqArrayLuma.size-1)
    diffChromaUAvg = diffChromaU / (searchSeqArrayLuma.size-1)
    diffChromaVAvg = diffChromaV / (searchSeqArrayLuma.size-1)
    
    auxDiffLuma[x] = diffLuma / (searchSeqArrayLuma.size-1)
    auxDiffCu[x] = diffChromaU / (searchSeqArrayLuma.size-1)
    auxDiffCv[x] = diffChromaV / (searchSeqArrayLuma.size-1)
    
    if (searchSeqArrayLuma.size-1)==0
      auxDiffLuma[x] = diffLuma
      auxDiffCu[x] = diffChromaU
      auxDiffCv[x] = diffChromaV
    end
  
    ##Distance between vectors
    #
    (0..(searchSeqArrayLuma.size-1)).each do |v|
      distLuma[v] = (searchSeqArrayLuma[v].to_f - tempArrayLuma[v].to_f).abs
      distChromaU[v] = (searchSeqArrayChromaU[v].to_f - tempArrayChromaU[v].to_f).abs
      distChromaV[v] = (searchSeqArrayChromaV[v].to_f - tempArrayChromaV[v].to_f).abs
    end
    sqrtLuma = sqrtChromaU = sqrtChromaV = 0.0
    distLuma.each { |v| sqrtLuma += v*v}
    distChromaU.each { |v| sqrtChromaU += v*v}
    distChromaV.each { |v| sqrtChromaV += v*v}
    
    sqrtLuma = Math.sqrt(sqrtLuma) if !sqrtLuma.nan?
    sqrtChromaU = Math.sqrt(sqrtChromaU) if !sqrtChromaU.nan?
    sqrtChromaV = Math.sqrt(sqrtChromaV) if !sqrtChromaV.nan?
    
    auxSqrtLuma[x] = sqrtLuma
    auxSqrtCu[x] = sqrtChromaU
    auxSqrtCv[x] = sqrtChromaV
  
  end
  
  #normalize difference between vectors
  (0..(auxDiffLuma.size-1)).each do |a|
    lowerLuma = auxDiffLuma[a].to_f if auxDiffLuma[a].to_f < lowerLuma
    higherLuma = auxDiffLuma[a].to_f if auxDiffLuma[a].to_f > higherLuma
    lowerChromaU = auxDiffCu[a].to_f if auxDiffCu[a].to_f < lowerChromaU
    higherChromaU = auxDiffCu[a].to_f if auxDiffCu[a].to_f > higherChromaU
    lowerChromaV = auxDiffCv[a].to_f if auxDiffCv[a].to_f < lowerChromaV
    higherChromaV = auxDiffCv[a].to_f if auxDiffCv[a].to_f > higherChromaV
  end
  
  aux = 0
  (0..(auxDiffLuma.size-1)).each do |a|
    auxDiffLuma[aux] = (auxDiffLuma[a].to_f - lowerLuma)/(higherLuma-lowerLuma)
    auxDiffCu[aux] = (auxDiffCu[a].to_f - lowerChromaU)/(higherChromaU-lowerChromaU)
    auxDiffCv[aux] = (auxDiffCv[a].to_f - lowerChromaV)/(higherChromaV-lowerChromaV)
    aux += 1
  end
  
  lowerLuma = 1000000
  higherLuma = 0
  lowerChromaU = 1000000
  higherChromaU = 0
  lowerChromaV = 1000000
  higherChromaV = 0

  #normalize distance between vectors
  (0..(auxSqrtLuma.size-1)).each do |a|
    lowerLuma = auxSqrtLuma[a].to_f if auxSqrtLuma[a].to_f < lowerLuma
    higherLuma = auxSqrtLuma[a].to_f if auxSqrtLuma[a].to_f > higherLuma
    lowerChromaU = auxSqrtCu[a].to_f if auxSqrtCu[a].to_f < lowerChromaU
    higherChromaU = auxSqrtCu[a].to_f if auxSqrtCu[a].to_f > higherChromaU
    lowerChromaV = auxSqrtCv[a].to_f if auxSqrtCv[a].to_f < lowerChromaV
    higherChromaV = auxSqrtCv[a].to_f if auxSqrtCv[a].to_f > higherChromaV
  end

  aux = 0
  (0..(auxSqrtLuma.size-1)).each do |a|
    auxSqrtLuma[aux] = (auxSqrtLuma[a].to_f - lowerLuma)/(higherLuma-lowerLuma)
    auxSqrtCu[aux] = (auxSqrtCu[a].to_f - lowerChromaU)/(higherChromaU-lowerChromaU)
    auxSqrtCv[aux] = (auxSqrtCv[a].to_f - lowerChromaV)/(higherChromaV-lowerChromaV)
    aux += 1
  end
  
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
    
    partNumb = x%part
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
  
    #sleep = x if score >= 0.6
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
      print("%5.2f" % (scoreTotal*100.0), "% Hit: Video segment found in #{video} [#{realFrame}~#{realFrame+lengthSec}]\n")
      #print(realFrame, ".", partNumb, " LDiff:", "%2.6f" % auxDiffLuma[x], " LVectD:", "%2.6f" % auxSqrtLuma[x])
      #print(" CuDiff:", "%2.6f" % auxDiffCu[x] , " CuVectD:", "%2.6f" % auxSqrtCu[x])
      #print(" CvDiff:", "%2.6f" % auxDiffCv[x] , " CvVectD:", "%2.6f" % auxSqrtCv[x])
      #print(" TaniL:", "%2.3f" % taniLuma[x] , " TaniCU:", "%2.3f" % taniChromaU[x] , " TaniCV:", "%2.3f" % taniChromaV[x])
      #print("\n")
      #sleepT = x
      #sleep = x
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

print("Database clustering saved an average of ","%5.2f" % (savingsLuma/(videoArray.size-1)),"% on Luma, ", "%5.2f" % (savingsChromaU/(videoArray.size-1)),"% on ChromaU, ", "%5.2f" % (savingsChromaV/(videoArray.size-1)),"% on ChromaV", "\n")
print("Test run-time for #{videoArray.size} movies was ","%5.2f" % (Time.new-stime), " seconds\n")