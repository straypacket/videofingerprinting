#Usage
#vfp_table_stats

#INCLUDES
require 'rubygems'
require 'complex'
require 'sqlite3'

#VARIABLES
@@param = Array.new
@@param = [1,2,3,5,10,15,20,25,30]

(3..ARGV.size-1).each do |arg|
  if ARGV[arg] == "-debug"
    puts("Debug ON")
    debug = true
  #else
  #  raise RuntimeError, "Illegal command!"
  end
end

@@param.each do |db_t|
	#counters
	idx_avg = 0
	idx_counter = 0
	luma_avg = 0
	luma_counter = 0
	idx_dist_avg = 0
	idx_dist_counter = 0
	luma_dist_avg = 0
	luma_dist_counter = 0
	movie_array = Array.new

	#Initialization of database
	db = SQLite3::Database.new( "/home/gsc/test_suj_branch2_central_#{db_t}.db" )

	#Number of indexes
	db.execute("select * from allmovies").each do |movie|
		idx_avg += db.execute( "select count(*) from '#{movie[1]}'" )[0][0].to_i
		idx_counter += 1
	end
	
	#Distance between indexes
	db.execute("select * from allmovies").each do |movie|
		movie_array = db.execute( "select * from '#{movie[1]}'" )
		(0..movie_array.size-2).each do |row|
			idx_dist_avg += movie_array[row+1][0].to_f - movie_array[row][0].to_f
			luma_dist_avg += (movie_array[row+1][1].to_f - movie_array[row][1].to_f).abs
			luma_avg += movie_array[row][1].to_f
			luma_dist_counter += 1
			idx_dist_counter += 1
			luma_counter += 1
		end
	end
	
	db.close()

	print("Database #{db_t} avg idx = ","%5.2f" % (idx_avg/idx_counter)," | " ,"avg luma = ","%5.2f" % (luma_avg/luma_counter/100.0), "\n")
	print("Database #{db_t} avg idx dist = ","%5.2fs" % (idx_dist_avg/idx_dist_counter)," | ", "avg luma dist = ","%5.2f" % (luma_dist_avg/luma_dist_counter/100.0), "\n")
	
end