#!/usr/bin/ruby

require 'date'
require 'md5'
require 'fileutils'
require 'rexml/document'
require 'net/http'
require 'net/https'
include REXML

class Account
	attr_reader :id
	attr_accessor :months, :name, :current_month  #, :reminders

	def initialize(name="New Account")
		@id = MD5.new(Time.now.to_s).to_s
		@name = name 
		@months = []
		m = Month.new
		add_month(m)
		@current_month = @months.first
	#	@reminders = []
	end

#	def add_reminder(note, date={})
#		t = Date.today
#		day_info = {:day => t.day, :month => t.month, :year => t.year}.merge(date)
#		r = Reminder.new
#		r.note = note
#		r.day = day_info[:day]
#		r.month = day_info[:month]
#		r.year = day_info[:year]
#		@reminders << r
#	end
#
#	def todays_reminders
#		t = Date.today
#		day_info = {:day => t.day, :month => t.month, :year => t.year}.merge(date)
#		@reminders.select do |r|
#			the_day = Date::civil(day_info[:year],day_info[:month],day_info[:day])
#			day_info[:day] = (the_day + 1).day
#			r.day == day_info[:day] and
#			r.month == day_info[:month] and
#			r.year == day_info[:year] }.collect{|r| r.note}
#		end
#	end

	def get_name
		puts "Enter Account Name > "
		@name = gets.chomp
		@name
	end

	def get_month(month,year=nil)
		unless the_month = @months.select{|x| x.month == month and x.year == (year || Time.now.year)}.last
			m = Month.new(month,year)
			add_month(m)
			the_month = get_month(month,year)
		end
		the_month
	end

	def add_month(month)
		balance_forward(month)
		@months << month
		@months.sort!{|x,y| x.year * 100  + x.month <=> y.year * 100  + y.month}
	end

	def set_month(month,year)
		@current_month = get_month(month,year)
	end

	def balance_forward(month)
		if previous_month = @months.last
			if previous_month.month < month.month and previous_month.year == month.year
				do_balance_forward(previous_month,month)
			end
			if previous_month = @months.select{|m| m.month < month.month and m.year == month.year}.last
				do_balance_forward(previous_month,month)
			end
		end
	end

	def do_balance_forward(previous_month,current_month)
		current_month.start_balance = previous_month.end_balance
		current_month.update
	end

end

class Month
	attr_reader :month, :year, :start_balance, :end_balance, :balances, :xtns

	def initialize(month=nil,year=nil,balance=0.0)
		time = Time.now
		@month = month || time.month
		@year = year || time.year
		@xtns = []
		@balances = []
		@start_balance = balance
		@end_balance = 0.0
	end


	def start_balance=(bal)
		@start_balance = bal
		update
	end


	def add(options)
		@xtns << Xtn.new(options)
		update
	end

#	def delete(id)
#		@xtns.delete_at(@xtns.index(@xtns.select{|x| x.id == id}))
#		crunch
#	end

	def delete_at(index)
		@xtns.delete_at(index)
		update
	end

	def find(id)
		@xtns.select{|x| x.id == id}.first
	end

	def find_at(index)
		@xtns[index]
	end

	def move_to(source,dest)
		unless dest >= @xtns.size - 1
			xtn = @xtns[source].dup
			@xtns.delete_at(source)
			@xtns.insert(dest,xtn)
		end
		update
	end

	def update
		sort_xtns
		crunch
	end

	def name
		%w{January February March April May June July August September October November December}[month - 1] + " " + year.to_s
	end

	def current_balance
		time = Time.now
		if @month == time.month and @year == time.year
			balances = []
			xtn_set = @xtns.select{|x| x.day.to_i <= time.day}
			xtn_set.size.times do |x_index|
				if x_index == 0
					balances << @start_balance.to_f + xtn_set[x_index].amount
				else
					balances << xtn_set[x_index].amount + balances[x_index-1]
				end
			end
			balances.last || @start_balance || 0.0
		else
			@end_balance 
		end
	end

	def tag_summary
		tags = []
		@xtns.each do |xtn|
			xtn.tags.each{|t| tags << t}
		end
		summary = {}
		tags.collect{|tag| summary[tag.to_sym] ||= {:count => 0};  summary[tag.to_sym][:count] += 1}
		tags.uniq.sort.collect do |tag|
			sum = 0.0
			find_by_tag(tag).collect{|t| sum += t.amount}
			summary[tag.to_sym] = { :tag => tag, :count => summary[tag.to_sym][:count], :amount => sum}
		end
		summary
	end

	def find_by_tag(tag)
		return [] unless tag.class == String
		@xtns.select{|x| x.tags.include?(tag)}
	end

	def income
		sum = 0.0
		xtns.select{|x| x.amount > 0}.each{|x| sum += x.amount}
		sum
	end

	def expenses
		sum = 0.0
		xtns.select{|x| x.amount < 0}.each{|x| sum += x.amount}
		sum
	end

	private

	def crunch
		@balances = []
		@xtns.size.times do |x_index|
			if x_index == 0
				@balances << @start_balance.to_f + @xtns[x_index].amount.to_f
			else
				@balances << @xtns[x_index].amount + @balances[x_index-1]
			end
		end
		if @xtns.empty?
			@end_balance = @start_balance.to_f
		else
			@end_balance = @balances.last
		end
	end

	def sort_xtns
		days = @xtns.collect{|x| x.day}.uniq.sort
		sorted = []
		days.each do |day|
			sorted += @xtns.select{|x| x.day == day}
		end
		@xtns = sorted
	end
end

class Xtn
	attr_accessor  :day, :amount, :note
	attr_reader :id, :tags

	def initialize(options)
		time = Time.now
		@id = MD5.new(Time.now.to_s+rand(100).to_s).to_s
		@amount = options[:amount].to_f || 0.0
		@note = options[:note] || ""
		@day = options[:day] || time.day
		@tags = []
		if options[:tags]
			options[:tags].each do |tag|
				add_tag(tag)
			end
		end
	end

	def to_s
		"[#{year}-#{month}-#{day}] $#{amount} - #{note}"
	end

	def add_tag(tag)
		@tags << tag.to_s.strip
		@tags.sort!.uniq!
	end

	def remove_tag(tag)
		@tags.reject!{|t| t == tag}
	end
end

class Reminder
	attr_reader :id
	attr_accessor :day, :month, :year, :note

	def initialize
		@id = MD5.new(Time.now).to_s
	end
end

class FinanceManager

	# for debug
	attr_reader :accounts
  
	def initialize(filename=nil)
		@basedir = `echo $HOME`.chomp + "/.finman/"
		FileUtils.mkdir(@basedir) unless File.directory?(@basedir)
		@filename = @basedir + (filename || "finman.data")
		load_data(@filename)
		@help = false
		@live = true
		@accounts << (@current_account = Account.new) unless @current_account = @accounts.first
		time = Time.new
		@current_account.set_month(time.month,time.year)
		@show_calendar = false
		@message = nil
		@mode = :xtn
		@errors = []
	end
	
	def mainloop
		while @live do
			show_ui
			process_input(get_input)
			write_data
		end
	end

	private

	def load_data(filename=@filename)
		if File.exist?(filename)
			data = File.new(filename,"r")
			@accounts = Marshal.load(data.read)
		else
			@accounts = [Account.new]
		end
		rescue
			@accounts = [Account.new]
	end

	def write_data(filename=@filename)
		data = File.new(filename,"w")
		data.puts Marshal.dump(@accounts)
		ensure
			data.close
	end

	def show_ui
		system("clear")

		if @message
			puts @message
			puts
			@message = nil
		end

		unless @errors.empty?
			puts "Error!: #{@errors.join(', ')}"
			puts
			@errors = []
		end

		puts "=== Finance Manager ============="
		puts "[#{Time.now.to_s}]"
		puts `cal`.gsub(/^/,"    ") if @show_calendar
		show_accts
		puts "--------------------------------------------\n"

		case @mode
			when :xtn 
				show_xtns
			when :summary
				show_summary
			when :help
				show_help
		end

		print "> "
	end

	def process_input(input="")
		case input
			when "q"
				@live = false
				backup_data
			when "h"
				show_help
			when "a"
				add_xtn
			when "dump"
				dump_vars
			when "d"
				del_xtn
			when "mt"
				move_xtn
			when "cm"
				change_month
			when "esb"
				set_start_balance
			when "et"
				edit_xtn
			when "ca"
				change_account
			when "ea"
				edit_account_name
			when "na"
				new_account
			when "da"
				delete_account
			when "save"
				backup_data
			when "load"
				load_backup
			when "cal"
				@show_calendar = ! @show_calendar
			when "getnew"
				update_xtns_from_web
			when "sum"
				summary_mode
			when "xtn"
				xtn_mode
			when "mode"
				pick_mode
		end
	end

	def xtn_mode
		@mode = :xtn
	end

	def summary_mode
		@mode = :summary
	end

	def pick_mode
		@mode = :xtn
	end

	def load_backup
		puts "----------------------------"
		files = `ls #{@basedir}*.data`.split("\n").reject{|f| f.match("finman.data")}.sort
		files.each_index do |index|
			puts "[#{index+1}] #{files[index]}"
		end
		print "Select a file to load> "
		i = gets.chomp.to_i 

		if i > 0 and i <= files.size
			load_data(files[i -1])
			write_data
			initialize
		end
	end

	def backup_data
			filename = "#{@basedir}backup-#{Time.now.strftime("%Y%m%d-%H%M")}"
			write_data("#{filename}.data")
			de = DataExport.new
			de.delimited_converter_all(@accounts,"#{filename}.tab")
			de.xml_converter_all(@accounts,"#{filename}.xml")
	end

	def get_input
		gets.chomp
	end

	def new_account
		print "Create New Account. Account Name> "
		n = gets.chomp
		unless n.empty?
			@current_account = Account.new(n)
			@accounts << @current_account
		end
	end

	def edit_account_name
		print "Active Account Name [#{@current_account.name}]> "
		n = gets.chomp
		unless n.empty?
			@current_account.name = n
		end
	end

	def change_account
		print "Switch to Account #> "
		a = gets.chomp.to_i
		if a > 0 and a <= @accounts.size
			@current_account = @accounts[a-1]
		end
	end

	def delete_account
		print "Account to Delete> "
		a = gets.chomp.to_i
		if a > 0 and a <= @accounts.size
			puts "This will permanently delete records for [#{@accounts[a-1].name}]."
			puts "Enter the name of the account you wish to delete to confirm this action."
			print "[#{@accounts[a-1].name}]> "
			n = gets.chomp
			if n == @accounts[a-1].name
				@accounts.delete_at(a-1)
			end
			unless @current_account = @accounts.first
				@accounts << (@current_account = Account.new)
			end
		end
	end

	def edit_xtn
		print "Edit Transaction #> "
		t = gets.chomp.to_i
		if valid_xtn_number?(t)
			newinfo = {}
			x = @current_account.current_month.xtns[t - 1]
			
			print "Day [#{x.day}]> "
			d = gets.chomp
			newinfo[:day] = d unless d.empty?
			
			print "Amount [$#{x.amount}]> "
			a = gets.chomp
			newinfo[:amount] = a.to_f unless a.empty?
			
			print "Description [#{x.note}]> "
			de = gets.chomp
			newinfo[:note] = de unless de.empty?

			print "Tags [#{x.tags.join(',')}]> "
			tags = gets.chomp.split(',')

			x.day = newinfo[:day].to_i if newinfo[:day]
			x.amount = newinfo[:amount] if newinfo[:amount]
			x.note = newinfo[:note] if newinfo[:note]
			unless tags.empty?
				x.tags.each{|t| x.remove_tag(t)}
				tags.each{|t| x.add_tag(t)}
			end
			@current_account.current_month.update
		end
	end

	def show_xtns
		color = Color.new
		index = 1
		puts "  [Start Balance: $#{@current_account.current_month.start_balance}]"
		@current_account.current_month.xtns.each do |x|
			line = sprintf("  %2d. [%02d/%02d] $%8.2f - %-30s [%-15s] -- [$%8.2f]", 
						   index,@current_account.current_month.month,
						   x.day,
						   x.amount,
						   x.note,
						   x.tags.join(','),
						   @current_account.current_month.balances[index-1] )
			index += 1
			puts color.zebra(line)
		end
		puts "  [End Balance: $#{@current_account.current_month.end_balance}]"
	end

	def show_summary
		show_in_out
		puts
		show_tag_summary
	end

	def show_in_out
		puts sprintf(" * %-10s $%8.2f\n * %-10s $%8.2f\n * %-10s $%8.2f",
			"Income:",
			@current_account.current_month.income,
			"Expenses:",
			@current_account.current_month.expenses,
		    "Net:",
			@current_account.current_month.income + @current_account.current_month.expenses)
	end

	def show_tag_summary
		c = Color.new
		puts " * Tags"
		@current_account.current_month.tag_summary.to_a.sort{|x,y| y[1][:amount].abs <=> x[1][:amount].abs}.each do |tag|
			puts c.zebra(sprintf("  * %-10s (%2d)  $%8.2f  (%3d%%)",
						 tag[0].to_s, tag[1][:count], tag[1][:amount],
						 (tag[1][:amount] / @current_account.current_month.income * 100.0).abs))
		end
	end

	def show_accts
		account_names = @accounts.collect do |a|
				if a.name == @current_account.name
					prefix = " => "
				else
					prefix = "    "
				end
				sprintf("%3s%2d. [%-10s - %-15s] $%-8.2f",
							 prefix,
							@accounts.index(a) + 1,
							a.name,
							a.current_month.name,
							a.current_month.current_balance)
			end
		account_names.each{|a| puts a}
	end

	def show_help
		system("clear")
		puts "\n\n-----------------------------------------"
		puts "HELP!!!  Available commands."
		puts "Type a command at the prompt, hit enter, then follow any other prompts."
		puts "-----------------------"
		puts " (q) Quit"
		puts " (h) Help (this screen)"
		puts " (cal) Toggle Calendar"
		puts " (mode) Change Mode"
		puts " (sum) Summary Mode"
		puts " (xtn) Transaction Mode"
		puts "Transaction Functions"
		puts " (a) Add transaction"
		puts " (b) Delete transaction"
		puts " (et) Edit transaction"
		puts " (getnew) Get new transactions from web"
		puts "Account Functions"
		puts " (ea) Edit Account Name"
		puts " (cm) Change Month"
		puts " (esb) Edit Start Balance for current month"
		puts " (ca) Change Account"
		puts " (da) Delete Account"
		puts " (na) New Account"
		puts "Backup"
		puts " (save) Save data now"
		puts " (load) Load a backup"
		print "(Hit Enter to Continue.)"
		gets
		@mode = :xtn
	end

	def change_month
		print "Month (#)> "
		month = gets.chomp.to_i
		print "Year (####)> "
		year = gets.chomp.to_i
		if month > 0 and month < 13
			year = Time.now.year if year < 1
			@current_account.set_month(month,year)
		end
	end

	def add_xtn
		time = Time.now
		puts "Add Transaction:"

		print "Day> "
		day = gets.chomp.to_i
		day = time.day.to_i if day == 0

		print "Amount> "
		amt = gets.chomp.to_f
		
		print "Description> "
		desc = gets.chomp

		print "Tags> "
		tags = gets.chomp.split(",")
		@current_account.current_month.add(:amount => amt, :day => day, :note => desc, :tags => tags)
	end

	def del_xtn
		print "Enter # of Transaction to Delete> "
		n = gets.chomp.to_i
		if valid_xtn_number?(n) 
			@current_account.current_month.delete_at(n-1)
		end
	end

	def move_xtn
		print "Transaction to Move> "
		s = gets.chomp.to_i
		if valid_xtn_number?(s)
			print "Destination> "
			d = gets.chomp.to_i
			@current_account.current_month.move_to(s-1,d-1) if valid_xtn_number?(d)
		end
	end

	def valid_xtn_number?(number)
		number > 0 and number <= @current_account.current_month.xtns.size
	end

	def set_start_balance
		print "Starting Balance> "
		sb = gets.chomp.to_f
		@current_account.current_month.start_balance = sb
		@current_account.current_month.update
	end

	def dump_vars
		puts " * Accounts"
		puts @accounts.inspect
		@help = true
	end

	def tab_import(filename)
		file = File.new(filename,"r")
		transactons = file.readlines.collect{|t| t.split("\t")}
	end

	def update_xtns_from_web
		print "Fetching new transactions from RSS feed..."
		new_xtns = RssImport.new.transactions(@current_account.current_month.month,@current_account.current_month.year)
		puts "Done."
		new_xtns = new_xtns.delete_if do |new_xtn|
			not @current_account.current_month.xtns.select{|x| x.day == new_xtn.day and x.amount == new_xtn.amount}.empty?
		end
		new_xtns.each do |new_xtn|
			@current_account.current_month.xtns << new_xtn
		end
		@current_account.current_month.update
		@message = "Added #{new_xtns.size} transactions to this month."
	end

end

class DataExport
	def initialize(data_type="csv")
		@data_type = data_type
	end

	def delimited_converter_all(data,filename,delimiter="\t")
		outfile = File.new(filename,"w")
		outfile.puts  %w{"Account" "Date" "Amount" "Description" "Tags"}.join(delimiter)
		data.each do |account| 
			account.months.each do |month|
				month.xtns.each do |xtn|
					daystr = "#{month.year}/#{month.month}/#{xtn.day}"
					outfile.puts [account.name,daystr,xtn.amount,xtn.note,xtn.tags.join(',')].collect{|f| '"' + f.to_s + '"'}.join(delimiter)
				end
			end
		end
		ensure
			outfile.close
	end


	def xml_converter_all(data,filename)

		dtd = <<EOF
<!DOCTYPE financedata [
  <!ELEMENT financedata		(export_date,account+)>
  <!ELEMENT account			(id,name,month*)>
  <!ELEMENT month			(month_number,year_number,start_balance,end_balance,transaction*)>
  <!ELEMENT transaction		(id,amount,note,day,tag*)>
  <!ELEMENT export_date		(#PCDATA)>
  <!ELEMENT id				(#PCDATA)>
  <!ELEMENT name			(#PCDATA)>
  <!ELEMENT month_number	(#PCDATA)>
  <!ELEMENT year_number		(#PCDATA)>
  <!ELEMENT start_balance	(#PCDATA)>
  <!ELEMENT end_balance		(#PCDATA)>
  <!ELEMENT amount			(#PCDATA)>
  <!ELEMENT note			(#PCDATA)>
  <!ELEMENT day				(#PCDATA)>
  <!ELEMENT tag				(#PCDATA)>
]>
EOF
		xmlstring = "" + dtd
		file = File.new(filename,"w")
		doc = Document.new xmlstring
		doc << XMLDecl.new

		docroot = doc.add_element("financedata")
			expdate = docroot.add_element("export_date")
			expdate.text = Time.new.to_s
			data.each do |account|
				xmlaccount = docroot.add_element("account") 
				xmlaccountid = xmlaccount.add_element("id")
				xmlaccountid.text = account.id
				xmlaccountname = xmlaccount.add_element("name")
				xmlaccountname.text = account.name
				account.months.each do |month|
					xmlmonth = 	xmlaccount.add_element("month") 
					xmlmonthnumber = xmlmonth.add_element("month_number")
					xmlmonthnumber.text = month.month
					xmlyear = xmlmonth.add_element("year_number")
					xmlyear.text = month.year
					xmlstartbal = xmlmonth.add_element("start_balance")
					xmlstartbal.text = month.start_balance
					xmlendbal = xmlmonth.add_element("end_balance")
					xmlendbal.text = month.end_balance
					month.xtns.each do |xtn|
						xmlxtn = xmlmonth.add_element("transaction") 
						xmlxtnid = xmlxtn.add_element("id")
						xmlxtnid.text = xtn.id
						xmlxtnamt = xmlxtn.add_element("amount")
						xmlxtnamt.text = xtn.amount
						xmlxtnnote = xmlxtn.add_element("note")
						xmlxtnnote.text = xtn.note
						xmlxtnday = xmlxtn.add_element("day")
						xmlxtnday.text = xtn.day
						xtn.tags.each do |tag|
							xmltag = xmlxtn.add_element("tag") 
							xmltag.text = tag
						end
					end
				end		
			end
        file.puts doc.to_s(1)
    ensure
        file.close
	end

end


ImportXtn = Struct.new("ImportXtn", :date, :day, :month, :year, :amount, :description)
class RssImport
	def initialize
		@server = "moneytracker.goamplify.com"
		#@path = "/user/myfeeds/feeder?x=6163636F756E7449643D3430323838313861306230333232306530313062303563373538663230326565"
		@path = "/user/alerts/rss_search/0000001963?criteria="
		@username = '4426903'
		@password = 'sLMwG0T3VC'
		@transactions = nil
		@current_month = 0
		@current_year = 0
	end

	def transactions(month,year)
		if @transactions.nil? or @current_month != month or @current_year != year
			xtns = parse_rss(get_feed).select{|x| x.month == month.to_i and x.year == year.to_i}
			@transactions = xtns.collect do |x|
				this_xtn = Xtn.new({ :amount => x.amount,
									 :day => x.day,
									 :note => x.description,
									 :tags => []})
				this_xtn
			end
			@transactions.sort!{|x,y| x.day <=> y.day}
			@current_month = month
			@current_year = year
		end
		return @transactions
	#	rescue
		#	[]
	end

	private

	def get_feed
		http = Net::HTTP.new(@server,443)
		req = Net::HTTP::Get.new(@path)
		http.use_ssl = true
		req.basic_auth @username, @password
		response = http.request(req)
		return response.body
	end

	def parse_rss(xml_data)
		doc = REXML::Document.new(xml_data)
		transactions = []
		doc.elements.each('//channel/item') do |xtn|
			this_xtn = ImportXtn.new("foo")
			xtn_data = xtn.elements['title'].text.split(" - ")
			this_xtn.amount = xtn_data[0].gsub('$','').to_f
			this_xtn.date = xtn.elements['pubDate'].text
			this_xtn.description = xtn_data[1]
			daymatch_re = /[^0-9]+, ([0-9]{2}) ([a-z]+) ([0-9]{4}) /i
			daymatch = this_xtn.date.match(daymatch_re)
			this_xtn.day = daymatch[1].to_i
			this_xtn.month = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"].index(daymatch[2]) + 1
			this_xtn.year = daymatch[3].to_i
			transactions << this_xtn
		end
		transactions
	end
end

class Color
	COLORS = {
		:red => "31",
		:darkred => "1;31",
		:gray => "1;30",
		:blue => "34",
		:darkblue => "1;34",
		:black => "30",
		:white => "37",
		:blackbg => "40",
		:graybg => "47",
		nil => ""
	}

	def initialize
		@z = 1
	end

	def zebra(text,fgc=:black,default_bgc=:graybg)
		@z = @z * -1 + 1
		bgc = [nil,default_bgc][@z]
		color(text,fgc,bgc)
	end

	def red_negative(text)
		text.gsub(/\$(-[0-9]+\.?[0-9]{2}?)/,color('$\1',:red))
	end

	def color(text,color=nil,background=nil)
        bg = background ? "\033[#{COLORS[background]}m" : ""
		"#{bg}\033[#{COLORS[color]}m#{text}\033[0m"
	end
end



FinanceManager.new.mainloop
