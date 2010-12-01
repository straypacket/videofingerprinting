require 'rubygems'
require 'sqlite3'
#require 'mathn'
require 'matrix'
require 'complex'

nsegs = 0
nsegs2 = 0
ntime = 0
lumaThresh = 64
transitionMatrix = Array.new((256/lumaThresh.to_f).ceil) { Array.new((256/lumaThresh.to_f).ceil, 0) }
QMatrix = Array.new((256/lumaThresh.to_f).ceil) { Array.new((256/lumaThresh.to_f).ceil, 0) }
transitionMatrix2 = Array.new(((256/lumaThresh.to_f).ceil-1)*11+1) { Array.new((256/lumaThresh.to_f).ceil, 0) }

##
#Initialization of database
db = SQLite3::Database.new( "/home/gsc/test_suj_branch3_import.db" )

#First order
db.execute('select * from allmovies').each do |movie|
    #lsegs = 0
	#ltime = 0
	time = 0
	prev_luma = -1
	prev_prev_luma = -1
	#puts("[#{movie[1]}]")
	db.execute("select * from \"#{movie[1]}\"").each do |segment|
		#First order
		if ( (segment[1].to_f/100/lumaThresh).floor != prev_luma && prev_luma != -1 )
			#puts("Quant_level:#{prev_luma.to_s((256/lumaThresh.to_f).ceil)} => #{(segment[1].to_i/100/lumaThresh).ceil.to_s((256/lumaThresh.to_f).ceil)} Time:#{segment[0].to_f-time}") if segment[1].to_f/100/lumaThresh >= 0 && prev_luma != -1
			transitionMatrix[prev_luma][(segment[1].to_f/100/lumaThresh).floor] += 1
			QMatrix[prev_luma][(segment[1].to_f/100/lumaThresh).floor] += (segment[0].to_f-time).ceil
			nsegs += 1
			ntime += segment[0].to_f-time
			#lsegs += 1
			#ltime += segment[0].to_f-time
			time = segment[0].to_f
		end
		#Second order
		if ( (segment[1].to_f/100/lumaThresh).floor != prev_luma && prev_prev_luma != prev_luma && prev_prev_luma != -1 && prev_luma != -1 )
			transitionMatrix2[(prev_prev_luma.to_s+prev_luma.to_s).to_i][(segment[1].to_f/100/lumaThresh).floor] += 1
			nsegs2 += 1
		end

		prev_prev_luma = prev_luma
		prev_luma = (segment[1].to_f/100/lumaThresh).floor
	end

	#puts("T(%):")
	#transitionMatrix.each { |l| l.each { |e| print "%.2f " % (e.to_f/lsegs.to_f)  }; puts "" }
	#puts("Q(%):")
	#QMatrix.each { |l| l.each { |e| print "%.2f " % (e.to_f/ltime.to_f) }; puts "" }
	#transitionMatrix = Array.new((256/lumaThresh).ceil) { Array.new((256/lumaThresh).ceil, 0) }
	#QMatrix = Array.new((256/lumaThresh).ceil) { Array.new((256/lumaThresh).ceil, 0) }
	#puts("#Segs:#{nsegs} Time:#{ntime}")
end

#puts("T^1:")
#transitionMatrix.each { |l| p l}
#puts("T^2:")
#transitionMatrix2.each { |l| p l}
#puts("Q:")
#QMatrix.each { |l| p l}

sumT1 = 0
puts("T^1(%):")
from = 0
to = 0
print(" ")
(0..(256/lumaThresh.to_f).ceil-1).each { print("      #{to}"); to+=1 }
puts("")
transitionMatrix.each do |l| 
	max = 0
	print "#{from} | "
	from += 1
	l.each { |e| max+= e}
	l.each do |e|
		print "%.4f " % (e.to_f/nsegs.to_f)
		sumT1 += e.to_f
	end
	puts ""
end
puts("Sum T1: #{sumT1}/#{nsegs}")

sumT2 = 0
puts("T^2(%):")
from = 0
to = 0
print(" ")
(0..(256/lumaThresh.to_f).ceil-1).each { print("      #{to}"); to+=1 }
puts("")
transitionMatrix2.each do |l| 
    if (from%10) < (256/lumaThresh.to_f).ceil
		max = 0
		if from%10 != from/10
			print "#{from} | " if from > 9
			print "0#{from} | " if from <= 9

			l.each { |e| max+= e }
			l.each do |e|
				print "%.4f " % (e.to_f/nsegs2.to_f) if (e.to_f/nsegs2.to_f).nan? == false
				print "0.0000 " if (e.to_f/nsegs2.to_f).nan? == true
				sumT2 += e.to_f
			end
			puts ""
		end
	end
	from += 1
end
puts("Sum T2: #{sumT2}/#{nsegs2}")

puts("Q(%):")
QMatrix.each do |l|
	#max = 0
	#l.each { |e| max+= e}
	l.each do |e|
		print "%.4f " % (e.to_f)
		#print "%.4f " % (e.to_f/ntime.to_f)
		#print "%.4f " % (e.to_f/max.to_f)
	end
	puts ""
end