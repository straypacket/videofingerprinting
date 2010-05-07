#Usage
#avisynthLuma sourceVideo start length

#Throughout this program, CLIP is the small sequence we want to find, MOVIE is the big sequence we want to search into

#INCLUDES
#
require 'rubygems'
require 'complex'
require 'sqlite3'

#VARIABLES
#
linux = false

(4..ARGV.size-1).each do |arg|
  if ARGV[arg] == "-linux"
    linux = true
    path = '/mnt/AviSynthVideos/'
  elsif ARGV[arg] == "-way"
    way = ARGV[arg+1].to_f
    puts("Selecting way (prelem=#{way})")
  #else
  #  raise RuntimeError, "Illegal command!"
  end
end

#Remaining auxiliary variables
#
sourceVideo = ARGV[0]
videoArray = Array.new

##searchSeqArray operations
#
@@firstSec = ARGV[1].to_i
@@lengthSec = ARGV[2].to_i
#total movie arrays
fps = 0.0

##
#Initialization of databases
db = SQLite3::Database.new( "/home/gsc/test_cgo_modelling_temp.db" )
#
begin
	db.execute("select * from allmovies").each do |movie|
		videoArray << movie[1]
	end
rescue
	raise RuntimeError, "Problems reading the \"allmovies\" table! Did you run the videofingerprint.c program beforehand?"
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
videoArray.delete(sourceVideo)
videoArray.unshift(sourceVideo)

targetVideo = Array.new()

videoArray.each do |video|
	p "Analyzing #{video} ..."
	#re-init params
	fps = 0.0
	currentVideo = Array.new()
  
	begin
		#Get movie information from database, each line represents a frame
		query = db.execute( "select * from '#{video}'" )
	rescue
		raise RuntimeError, "Video #{video} is still not in database! Did you run the videofingerprint.c program beforehand?"
	end
	
	begin
		#Get movie framerate
		fps = db.execute( "select * from allmovies where name = \"#{video}\"")[0][2].to_f
	rescue
		raise RuntimeError, "Video #{video} has no fps info in database! Did you run the videofingerprint.c program beforehand?"
	end
	raise RuntimeError, "Wrong FPS value for file #{video}" if fps == 0.0
	
	#Read each row (represents a frame) and put the values in an array
	rows = query[0..-1].size
	
	rows.times { currentVideo << Array.new(8) }

	if rows > 0
		rows.times do |f|
			currentVideo[f][0..7] = query[f][1..8]
		end
	elsif
		raise RuntimeError, "Video #{video} has no information! Did you run the videofingerprint.c program beforehand?"
	end
	
	aux = 0
	if video == sourceVideo
		targetVideo = Array.new()
		p "Analyzing Target video"
		((@@firstSec*fps).round..(@@firstSec*fps+@@lengthSec*fps).round).each do |a|
			targetVideo << Array.new(7)
			#p targetVideo
			#p "Inserting frame #{a}"
			(0..7).each do |b|
				#p "Inserting cgo value #{currentVideo[a][b]} into targetVideo[#{aux}][#{b}]"
				targetVideo[aux][b] = currentVideo[a][b]
			end
			aux = aux + 1
		end
	end
	
	####
	# Video search
	####
		
	(0..currentVideo.size-1).each do |c|
		totalDistV = 0.0
		if c+targetVideo.size < currentVideo.size
			(c..c+targetVideo.size-1).each do |f|
				#puts "Comparing #{video}[#{f}] with #{sourceVideo}[#{f-c}]\n #{currentVideo[f]}\n #{targetVideo[f-c]}"
				totalDistV += vectD(currentVideo[f],targetVideo[f-c]) if currentVideo[f] != nil || targetVideo[f-c] != nil
			end
			totalDistV = totalDistV/(targetVideo.size-1)
			p "Match found in video #{video} for frames #{c}~#{c+(targetVideo.size)}. Value of match is #{totalDistV}" if totalDistV < 0.2
		end
	end
	
end