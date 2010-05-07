#Usage
#avisynthLuma sourceVideo start length

#Throughout this program, CLIP is the small sequence we want to find, MOVIE is the big sequence we want to search into

#INCLUDES
#
require 'rubygems'
require 'complex'
require 'sqlite3'

lumaArray = Array.new

##
#Initialization of databases
db = SQLite3::Database.new( "/home/gsc/test_suj_newtable_0.1_lut.db" )
#

db.execute("select * from hashluma").each do |luma|
	if luma[1] != nil
		lineArray = Array.new
		lineArray = luma[1].split(",")
		count = 0
		sum = 0
		(0..lineArray.size-1).each do |e|
			count += 1
			sum += lineArray[e].split(":")[1].to_i
		end
		
		lumaArray << (sum*1.0)/(count*1.0)
	end
	lumaArray << "0" if luma[1] == nil
end

#db.execute("select * from hashluma").each do |luma|
#	if luma[1] != nil
#		lineArray = Array.new
#		lineArray = luma[1].split(",")
#		sum = ""
#		(0..lineArray.size-1).each do |e|
#			sum = "#{sum} #{lineArray[e].split(":")[1].to_i}"
#		end
#		
#		lumaArray << sum
#	end
#	lumaArray << "0" if luma[1] == nil
#end

##
#CODE

(0..lumaArray.size-1).each do |l|
	puts("#{l},#{lumaArray[l]}")
end
