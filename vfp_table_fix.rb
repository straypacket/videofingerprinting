#Usage
#vfp_table_stats

#INCLUDES
require 'rubygems'
require 'complex'
require 'sqlite3'

(3..ARGV.size-1).each do |arg|
  if ARGV[arg] == "-debug"
    puts("Debug ON")
    debug = true
  #else
  #  raise RuntimeError, "Illegal command!"
  end
end

first_dbs=[]#"cif","brate","fps"]
second_dbs=["gray"]#"qcif","5fps"]

first_dbs.each do |db|
	db = SQLite3::Database.new( "/home/gsc/test_suj_branch2_central_#{db}.db" )

	movies = Array.new
	db.execute("SELECT * FROM main.sqlite_master WHERE type='table'").each do |row|
		movies << row[2] if row[2] != "allmovies"
	end

	new_movies = Array.new
	movies.each do |m|
		tmp = m.split('.')
		new_movies << "#{tmp[0]}.#{tmp[1]}"
	end

	(0..movies.size-1).each do |c|
		#db.execute("ALTER TABLE '#{movies[c]}' RENAME TO '#{new_movies[c]}'")
		#db.execute("UPDATE allmovies SET name='#{new_movies[c]}' WHERE name='#{movies[c]}'")
	end

	db.close()
end

second_dbs.each do |db|
	db = SQLite3::Database.new( "/home/gsc/test_suj_branch2_central_#{db}.db" )

	movies = Array.new
	db.execute("SELECT * FROM main.sqlite_master WHERE type='table'").each do |row|
		movies << row[2] if row[2] != "allmovies"
	end

	new_movies = Array.new
	movies.each do |m|
		tmp = m.split('.')
		new_movies << "#{tmp[1]}.#{tmp[2]}"
	end

	(0..movies.size-1).each do |c|
		db.execute("ALTER TABLE '#{movies[c]}' RENAME TO '#{new_movies[c]}'")
		db.execute("UPDATE allmovies SET name='#{new_movies[c]}' WHERE name='#{movies[c]}'")
	end

	db.close()
end