require 'rubygems'
require 'sqlite3'
#require 'mathn'
require 'matrix'
require 'complex'

if ARGV[0] != nil
	limit = ARGV[0]
else
	limit = -1
end
	
nsegs0 = 0
nsegs = 0
nsegs2 = 0
nsegs3 = 0
gsegs = 0
ntime = 0
lumaThresh = 16
lArray = Array.new
("A".."ZZZ").each { |l| lArray << l}
QMatrix = Array.new((256/lumaThresh.to_f).ceil) { Array.new((256/lumaThresh.to_f).ceil, 0) }
transitionMatrix0 = Array.new((256/lumaThresh.to_f).ceil, 0)
transitionMatrix = Array.new((256/lumaThresh.to_f).ceil) { Array.new((256/lumaThresh.to_f).ceil, 0) }
transitionMatrix2 = Array.new((((256/lumaThresh.to_f).ceil).to_s+((256/lumaThresh.to_f).ceil).to_s).to_i) { Array.new((256/lumaThresh.to_f).ceil, 0) }
#transitionMatrix2 = Array.new(((256/lumaThresh.to_f).ceil-1)*11+1) { Array.new((256/lumaThresh.to_f).ceil, 0) }
transitionMatrix3 = Array.new((((256/lumaThresh.to_f).ceil).to_s+((256/lumaThresh.to_f).ceil).to_s+((256/lumaThresh.to_f).ceil).to_s).to_i) { Array.new((256/lumaThresh.to_f).ceil, 0) }
#transitionMatrix3 = Array.new(((256/lumaThresh.to_f).ceil-1)*111+1) { Array.new((256/lumaThresh.to_f).ceil, 0) }

##
#Initialization of database
db = SQLite3::Database.new( "/home/gsc/test_suj_branch3_import.db" )

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
		nsegs0 += 1
		gsegs += 1
		#First order
		if ( prev_luma != -1 )
			#puts("Quant_level:#{prev_luma.to_s((256/lumaThresh.to_f).floor)} => #{(segment[1].to_i/100/lumaThresh).floor.to_s((256/lumaThresh.to_f).ceil)} Time:#{segment[0].to_f-time}") if segment[1].to_f/100/lumaThresh >= 0 && prev_luma != -1
			transitionMatrix[prev_luma][(segment[1].to_f/100/lumaThresh).floor] += 1
			QMatrix[prev_luma][(segment[1].to_f/100/lumaThresh).floor] += (segment[0].to_f-time).floor
			nsegs += 1
			ntime += segment[0].to_f-time
			#lsegs += 1
			#ltime += segment[0].to_f-time
		end
		#Second order
		if ( prev_prev_luma != -1 && prev_luma != -1 )
			#puts("transitionMatrix2[#{(prev_prev_luma.to_s+prev_luma.to_s).to_i}][#{(segment[1].to_f/100/lumaThresh).floor}] += 1")
			transitionMatrix2[(prev_prev_luma.to_s+prev_luma.to_s).to_i][(segment[1].to_f/100/lumaThresh).floor] += 1
			nsegs2 += 1
		end
		#Third order
		if ( prev_prev_prev_luma != -1 && prev_prev_luma != -1 && prev_luma != -1 )
			transitionMatrix3[(prev_prev_prev_luma.to_s+prev_prev_luma.to_s+prev_luma.to_s).to_i][(segment[1].to_f/100/lumaThresh).floor] += 1
			nsegs3 += 1
		end		

		prev_prev_prev_luma = prev_prev_luma
		prev_prev_luma = prev_luma
		prev_luma = (segment[1].to_f/100/lumaThresh).floor
	end
end

#puts("T^1:")
#transitionMatrix.each { |l| p l}
#puts("T^2:")
#transitionMatrix2.each { |l| p l}
#puts("Q:")
#QMatrix.each { |l| p l}

puts("Markov chain states:")
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
transitionMatrix.each do |l| 
	max = 0
	print "#{lArray[from%((256/lumaThresh.to_f).ceil)]} | "
	from += 1
	l.each { |e| max+= e}
	l.each do |e|
		if (e.to_f/max.to_f) >= 0.0001
			print "%.4f " % (e.to_f/max.to_f)
		elsif (e.to_f/max.to_f) < 0.0001 && (e.to_f/max.to_f) > 0.0
			print "0.0001 "
		else
			print "0.0000 "
		end
		sumT1 += e.to_f
	end
	puts ""
end

puts("Q(%):")
from = 0
to = 0
(0..(256/lumaThresh.to_f).ceil-1).each { print("      #{lArray[to]}"); to+=1 }
puts("")
QMatrix.each do |l|
	max = 0
	print "#{lArray[from%((256/lumaThresh.to_f).ceil)]} | "
	from += 1
	#l.each { |e| max+= e}
	l.each do |e|
		#if (e.to_f/max.to_f) >= 0.0001
		#	print "%.4f " % (e.to_f/max.to_f)
		#elsif (e.to_f/max.to_f) < 0.0001 && (e.to_f/max.to_f) > 0.0
		#	print "0.0001 "
		#else
		#	print "0.0000 "
		#end
		if (e.to_f/ntime.to_f) >= 0.0001
			print "%.4f " % (e.to_f/ntime.to_f)
		elsif (e.to_f/ntime.to_f) < 0.0001 && (e.to_f/ntime.to_f) > 0.0
			print "0.0001 "
		else
			print "0.0000 "
		end
	end
	puts ""
end

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
		if (e.to_f/gsegs.to_f) >= 0.0001
			print "%.4f " % (e.to_f/gsegs.to_f)
		elsif (e.to_f/gsegs.to_f) < 0.0001 && (e.to_f/gsegs.to_f) > 0.0
			print "0.0001 "
		else
			print "0.0000 "
		end
		#stability += ("%.4f " % (e.to_f/gsegs.to_f)).to_s
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
				if (transitionMatrix2[(pp.to_s+p.to_s).to_i][n].to_f/gsegs.to_f) >= 0.0001
					print "%.4f " % (transitionMatrix2[(pp.to_s+p.to_s).to_i][n].to_f/gsegs.to_f) if (transitionMatrix2[(pp.to_s+p.to_s).to_i][n].to_f/gsegs.to_f).nan? == false
				elsif (transitionMatrix2[(pp.to_s+p.to_s).to_i][n].to_f/gsegs.to_f) < 0.0001 && (transitionMatrix2[(pp.to_s+p.to_s).to_i][n].to_f/gsegs.to_f) > 0.0
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
					if (transitionMatrix3[(ppp.to_s+pp.to_s+p.to_s).to_i][n].to_f/gsegs.to_f) >= 0.0001
						print "%.4f " % (transitionMatrix3[(ppp.to_s+pp.to_s+p.to_s).to_i][n].to_f/gsegs.to_f) if (transitionMatrix3[(ppp.to_s+pp.to_s+p.to_s).to_i][n].to_f/gsegs.to_f).nan? == false
					elsif (transitionMatrix3[(ppp.to_s+pp.to_s+p.to_s).to_i][n].to_f/gsegs.to_f) < 0.0001 && (transitionMatrix3[(ppp.to_s+pp.to_s+p.to_s).to_i][n].to_f/gsegs.to_f) > 0.0
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