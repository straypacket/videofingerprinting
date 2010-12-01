require 'rubygems'
require 'sqlite3'
#require 'mathn'
require 'matrix'

#benchmarking
stime = Time.new

if ARGV[0] != nil
	limit = ARGV[0]
else
	limit = -1
end

symbLength = ARGV[1].to_i
symbLength = 5 if ARGV[1] == nil
debug = false
bench = false

(1..ARGV.size-1).each do |arg|
  if ARGV[arg] == "-debug"
    puts("Debug ON")
    debug = true
  elsif ARGV[arg] == "-bench"
    bench = true
  end
end

lumaThresh = 4
nsegms0 = 0
nsegms = 0
nsegms2 = 0
nsegms3 = 0
gsegms = 0
ntime = 0
lArray = Array.new
("A0".."Z9").each { |l| lArray << l}
#QMatrix0 = Array.new((256/lumaThresh.to_f).ceil, 0)
#QMatrix = Array.new((256/lumaThresh.to_f).ceil) { Array.new((256/lumaThresh.to_f).ceil, 0) }
transitionMatrix0 = Array.new((256/lumaThresh.to_f).ceil, 0)
transitionMatrix = Array.new((256/lumaThresh.to_f).ceil) { Array.new((256/lumaThresh.to_f).ceil, 0) }
#transitionMatrix2 = Array.new((((256/lumaThresh.to_f).ceil).to_s+((256/lumaThresh.to_f).ceil).to_s).to_i) { Array.new((256/lumaThresh.to_f).ceil, 0) }
#transitionMatrix3 = Array.new((((256/lumaThresh.to_f).ceil).to_s+((256/lumaThresh.to_f).ceil).to_s+((256/lumaThresh.to_f).ceil).to_s).to_i) { Array.new((256/lumaThresh.to_f).ceil, 0) }

##
#Initialization of database
db = SQLite3::Database.new( "/home/gsc/vfp_1250.db" )
#db = SQLite3::Database.new( "/home/gsc/test_suj_branch3_import.db" )

movieCounter = 0
#First order
db.execute('select * from allmovies').each do |movie|
	movieCounter+=1
	next if movieCounter >= limit.to_i && limit.to_i > 0
    #lsegs = 0
	#ltime = 0
	time = 0
	prev_luma = -1
	prev_prev_luma = -1
	prev_prev_prev_luma = -1
	#puts("[#{movie[1]}]")
	db.execute("select * from \"#{movie[1]}\"").each do |segment|
		#Order zero
		transitionMatrix0[(segment[1].to_f/100/lumaThresh).floor] += 1
		#QMatrix0[(segment[1].to_f/100/lumaThresh).floor] += segment[0].to_f-time
		nsegms0 += 1
		gsegms += 1
		#First order
		if ( prev_luma != -1 )
			transitionMatrix[prev_luma][(segment[1].to_f/100/lumaThresh).floor] += 1
			#QMatrix[prev_luma][(segment[1].to_f/100/lumaThresh).floor] += segment[0].to_f-time
			nsegms += 1
			ntime += segment[0].to_f-time
			#lsegms += 1
			#ltime += segment[0].to_f-time
		end
		#Second order
		#if ( prev_prev_luma != -1 && prev_luma != -1 )
		#	transitionMatrix2[(prev_prev_luma.to_s+prev_luma.to_s).to_i][(segment[1].to_f/100/lumaThresh).floor] += 1
		#	nsegms2 += 1
		#end
		#Third order
		#if ( prev_prev_prev_luma != -1 && prev_prev_luma != -1 && prev_luma != -1 )
		#	transitionMatrix3[(prev_prev_prev_luma.to_s+prev_prev_luma.to_s+prev_luma.to_s).to_i][(segment[1].to_f/100/lumaThresh).floor] += 1
		#	nsegms3 += 1
		#end		

		#prev_prev_prev_luma = prev_prev_luma
		#prev_prev_luma = prev_luma
		prev_luma = (segment[1].to_f/100/lumaThresh).floor
	end
end

#Final Markov Transition Matrices
t0Chain = Array.new() {Array.new(transitionMatrix0.size)}
t1Chain = Array.new(transitionMatrix.size) {Array.new()}

puts("Markov chain states:") if debug
puts("T^0(%):") if debug
to = 0
print(" ") if debug
(0..(256/lumaThresh.to_f).ceil-1).each { print("      #{lArray[to]}"); to+=1 } if debug
puts("") if debug
print("     ") if debug
max = 0
transitionMatrix0.each { |l| max += l.to_f}
transitionMatrix0.each do |e| 
	print "%.4f " % (e.to_f/max.to_f) if debug
	t0Chain << (e.to_f/max.to_f)
end
puts "" if debug

sumT1 = 0
puts("T^1(%):") if debug
from = 0
to = 0
print(" ") if debug
(0..(256/lumaThresh.to_f).ceil-1).each { print("      #{lArray[to]}"); to+=1 } if debug
puts("") if debug
transitionMatrix.each do |l| 
	max = 0
	print "#{lArray[from%((256/lumaThresh.to_f).ceil)]} | " if debug
	l.each { |e| max+= e}
	l.each do |e|
		t1Chain[from] << (e.to_f/max.to_f)
		if (e.to_f/max.to_f) >= 0.0001
			print "%.4f " % (e.to_f/max.to_f) if debug
		elsif (e.to_f/max.to_f) < 0.0001 && (e.to_f/max.to_f) > 0.0
			print "0.0001 " if debug
		else
			print "0.0000 " if debug
		end
		sumT1 += e.to_f
	end
	from += 1
	puts "" if debug
end

=begin
puts("Q^0(%):")
to = 0
from = 0
print(" ")
(0..(256/lumaThresh.to_f).ceil-1).each { print("      #{lArray[to]}"); to+=1 }
puts("")
print("     ")
max = 0
QMatrix0.each { |l| max += l.to_f}
QMatrix0.each do |e| 
	print "%.4f " % (e.to_f/transitionMatrix0[from].to_f/movieCounter)
	from += 1
end
puts ""

puts("Q^1(%):")
from = 0
to = 0
(0..(256/lumaThresh.to_f).ceil-1).each { print("      #{lArray[to]}"); to+=1 }
puts("")
QMatrix.each do |l|
	max = 0
	to = 0
	print "#{lArray[from%((256/lumaThresh.to_f).ceil)]} | "
	l.each do |e|
		if (e.to_f/transitionMatrix[from][to].to_f/movieCounter) >= 0.0001
			print "%.4f " % (e.to_f/transitionMatrix[from][to].to_f/movieCounter)
		elsif (e.to_f/transitionMatrix[from][to].to_f/movieCounter) < 0.0001 && (e.to_f/transitionMatrix[from][to].to_f/movieCounter) > 0.0
			print "0.0001 "
		else
			print "0.0000 "
		end
		to += 1
	end
	from += 1
	puts ""
end
=end

#Hashtable construction
movieCounter =0
segmentTable = Hash.new()
db.execute('select * from allmovies').each do |movie|
    movieCounter+=1
	next if movieCounter >= limit.to_i && limit.to_i > 0
	#db.execute("select * from \"#{movie[1]}\"").each { |segment| print("#{lArray[(segment[1].to_f/100/lumaThresh).floor]}") }
	#puts ""
	time = 0
	initTime = 0
	prevState = -1
	accProb = -1
	accStates = ""
	p movie if debug
	hitTime = 0
	nHitSegs = 1
	lsegs = 0
	db.execute("select * from \"#{movie[1]}\"").each do |segment|
	    if lsegs < 7
		  puts "Skipping segment #{lsegs}" if debug
		  lsegs+=1
		  initTime = segment[0].to_f
		  next
		end
		currState = (segment[1].to_f/100/lumaThresh).floor
		#print("#{lArray[currState]}:#{time}~#{segment[0].to_f}|")
		if prevState == -1
			#print("#{t0Chain[currState]} ")
			accProb = t0Chain[currState].to_f
		elsif prevState == -2
			accProb = t1Chain[prevState][currState].to_f
		else
			#print("#{t1Chain[prevState][currState]} ")
			accProb *= t1Chain[prevState][currState].to_f
		end
		accStates += lArray[currState]
		prevState = currState
		time = segment[0].to_f

		if accProb < 0.001 #&& accStates.length >= symbLength
			segmentTable[accStates] = Array.new() if segmentTable.has_key?(accStates) == false
			segmentTable[accStates] << "#{movie[0]}:#{initTime}~#{segment[0].to_f}|#{accStates}>"
			#hitTime += segment[0].to_f-initTime
			initTime = time
			accStates = ""
			#TODO: Use -2 or -1?
			prevState = -1
			#nHitSegs += 1
		end
	end
	lsegs = 0
	#p ">#{movie[0]}:FPed time #{hitTime} symbLength #{symbLength} avgSegTime #{hitTime/nHitSegs} "
	#p ""
	#p segmentTable
end

segmentTable.each { |k,v| p "#{k}=>#{v} " } if debug

print(limit, " %5.2f" % (Time.new-stime), "\n") if bench

=begin
puts("")

puts("Measured results:")
puts("T^0(%):")
to = 0
print(" ")
(0..(256/lumaThresh.to_f).ceil-1).each { print("      #{lArray[to]}"); to+=1 }
puts("")
print("     ")
max = 0
transitionMatrix0.each { |l| max += l.to_f}
transitionMatrix0.each do |e| 
	print "%.4f " % (e.to_f/max.to_f)
end
puts ""

sumT1 = 0
puts("T^1(%):")
from = 0
to = 0
print(" ")
(0..(256/lumaThresh.to_f).ceil-1).each { print("      #{lArray[to]}"); to+=1 }
puts("")
stability = ""
transitionMatrix.each do |l| 
	max = 0
	print "#{lArray[from%((256/lumaThresh.to_f).ceil)]} | "
	from += 1
	l.each { |e| max+= e}
	l.each do |e|
		if (e.to_f/gsegms.to_f) >= 0.0001
			print "%.4f " % (e.to_f/gsegms.to_f)
		elsif (e.to_f/gsegms.to_f) < 0.0001 && (e.to_f/gsegms.to_f) > 0.0
			print "0.0001 "
		else
			print "0.0000 "
		end
		#stability += ("%.4f " % (e.to_f/gsegms.to_f)).to_s
		sumT1 += e.to_f
	end
	puts ""
end
#puts("Stability: #{stability}")

sumT2 = 0
puts("T^2(%):")
to = 0
print("   ")
(0..(256/lumaThresh.to_f).ceil-1).each { print("      #{lArray[to]}"); to+=1 }
puts("")
(0..(256/lumaThresh.to_f).ceil-1).each do |pp|
	(0..(256/lumaThresh.to_f).ceil-1).each do |p|
		lineTotal = 0.0
		(0..(256/lumaThresh.to_f).ceil-1).each { |n| lineTotal += transitionMatrix2[(pp.to_s+p.to_s).to_i][n].to_f}
		if lineTotal > 0.0
			print "#{lArray[pp]}#{lArray[p]} | "
			(0..(256/lumaThresh.to_f).ceil-1).each do |n|
				if (transitionMatrix2[(pp.to_s+p.to_s).to_i][n].to_f/gsegms.to_f) >= 0.0001
					print "%.4f " % (transitionMatrix2[(pp.to_s+p.to_s).to_i][n].to_f/gsegms.to_f) if (transitionMatrix2[(pp.to_s+p.to_s).to_i][n].to_f/gsegms.to_f).nan? == false
				elsif (transitionMatrix2[(pp.to_s+p.to_s).to_i][n].to_f/gsegms.to_f) < 0.0001 && (transitionMatrix2[(pp.to_s+p.to_s).to_i][n].to_f/gsegms.to_f) > 0.0
					print "0.0001 "
				else
					print "0.0000 "
				end
				sumT2 += n.to_f
			end
			puts ""
		end
	end
end

sumT3 = 0
puts("T^3(%):")
to = 0
print("     ")
(0..(256/lumaThresh.to_f).ceil-1).each { print("      #{lArray[to]}"); to+=1 }
puts("")
(0..(256/lumaThresh.to_f).ceil-1).each do |ppp|
	(0..(256/lumaThresh.to_f).ceil-1).each do |pp|
		(0..(256/lumaThresh.to_f).ceil-1).each do |p|
			lineTotal = 0.0
			(0..(256/lumaThresh.to_f).ceil-1).each { |n| lineTotal += transitionMatrix3[(ppp.to_s+pp.to_s+p.to_s).to_i][n].to_f}
			if lineTotal > 0.0
				print "#{lArray[ppp]}#{lArray[pp]}#{lArray[p]} | "
				(0..(256/lumaThresh.to_f).ceil-1).each do |n|
					if (transitionMatrix3[(ppp.to_s+pp.to_s+p.to_s).to_i][n].to_f/gsegms.to_f) >= 0.0001
						print "%.4f " % (transitionMatrix3[(ppp.to_s+pp.to_s+p.to_s).to_i][n].to_f/gsegms.to_f) if (transitionMatrix3[(ppp.to_s+pp.to_s+p.to_s).to_i][n].to_f/gsegms.to_f).nan? == false
					elsif (transitionMatrix3[(ppp.to_s+pp.to_s+p.to_s).to_i][n].to_f/gsegms.to_f) < 0.0001 && (transitionMatrix3[(ppp.to_s+pp.to_s+p.to_s).to_i][n].to_f/gsegms.to_f) > 0.0
						print "0.0001 "
					else
						print "0.0000 "
					end
					sumT3 += n.to_f
				end
				puts ""
			end
		end
	end
end
=end