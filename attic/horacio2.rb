video = ARGV[0]
#Open file
log = File.open(video + ".log2","r")
puts("Reading #{video}.log2") if debug

def arrayCluster(array,param)
  arrayCluster = Hash.new()
  c = 0
  aux = 0

  (0..array.size-2).each do |elem|
    arrayCluster[c] = 0 if aux == 0
    #if we're looking for a piece in the DB where @@lengthSec has no min/max normalization gives problems.
    #therefore, every @@lengthSec*0.4 we also create a new index
    #TODO: play with this 0.4 threshold
    if ((array[c].to_f - array[elem].to_f).abs > array[c].to_f*param)
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

#Read each line (represents a frame) and put the values for L,Cu,Cv into their own array
log.each do |line|
  #Regex for lines starting with fps
  if line =~ /^fps/
	fps = line.split(" ")[1].to_f
	raise RuntimeError, "Wrong FPS value for file #{video}" if fps.nan?
	fps = fps.to_i
	puts("Reading FPS off log file (#{fps})") if debug
  else
	aux = line.split(";")
	#According to command-line flags, we chose if our luma type:
	#"avg" is the current frame average; "diff" is the difference of averages with the previous frame
	lumaArrayFrames[aux[0].to_i] = aux[2] if method == "avg"
	lumaArrayFrames[aux[0].to_i] = aux[3] if method == "diff"
	chromaUArrayFrames[aux[0].to_i] = aux[4]
	chromaVArrayFrames[aux[0].to_i] = aux[5]
  end
end
log.close

result = Array.new
result = arrayCluster(lumaArrayFrames,0.1)

p result