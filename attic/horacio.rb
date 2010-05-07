video = ARGV[1]
threshold = 0.005
lumaArrayFramesAvg = Array.new
lumaArrayFramesDiff = Array.new
@@keyArrayFrames = Array.new
parts = ARGV[0].to_i

#Open file
log = File.open(video,"r")
puts("Reading #{video}")

def findLowDiff(array, param, parts)
  arrayCluster = Array.new()
  area = 15000
  
  #Only get points near the cutting parts
  last = array.size-1

  segments = Array.new
  (1..parts-1).each {|p| segments << last/parts*p}
  segments.sort!
  
  p segments
  
  #For every frame
  (0..array.size-1).each do |elem|
    #if the diff of threshold is low add to cluster
	if ((array[elem].to_f + array[elem+1].to_f + array[elem+2].to_f + array[elem+3].to_f + array[elem+4].to_f + array[elem+5].to_f)/6 < param) 
		#and if it's close to the areas we want to cut ...
		segments.each do |s|
			#... up to a time threshold called area
			if (s > elem-area) && (s < elem+area)
				#add the element to the array
				arrayCluster << [elem,@@keyArrayFrames[elem].to_i]
			end
		end
	end
  end

  arrayCluster.uniq!
  return arrayCluster
end

def groupArray(array)

  groupedArray = Array.new
  (0..array.size-1).each do |elem|
  
	if (array[elem] - array[elem+1]) == 1
	  e = array[elem]
	else
	  s = array[elem]
	  grouped
	end
    
  end

end

#Read each line (represents a frame) and put the values for L,Cu,Cv into their own array
log.each do |line|
  aux = line.split(";")
  #According to command-line flags, we chose our luma type:
  #"avg" is the current frame average; "diff" is the difference of averages with the previous frame
  lumaArrayFramesAvg[aux[0].to_i] = aux[2]
  lumaArrayFramesDiff[aux[0].to_i] = aux[3]
  @@keyArrayFrames[aux[0].to_i] = aux[4]
end
log.close

result = Array.new
result = findLowDiff(lumaArrayFramesDiff, threshold, parts)

result.each do |tuple|
  puts("#{tuple[0]} is Key-frame\n") if tuple[1] == 1
  #puts("#{tuple[0]}\n") if tuple[1] == 0
end
#p result
#findCluster(result.sort)