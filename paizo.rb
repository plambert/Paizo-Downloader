#!/usr/bin/env ruby

require 'rubygems'
require 'mechanize'
require 'highline/import'
require 'logger'
require 'irb'

log=Logger.new(STDERR)

module IRB # :nodoc:
  def self.start_session(binding)
    unless @__initialized
      args = ARGV
      ARGV.replace(ARGV.dup)
      IRB.setup(nil)
      ARGV.replace(args)
      @__initialized = true
    end

    workspace = WorkSpace.new(binding)

    irb = Irb.new(workspace)

    @CONF[:IRB_RC].call(irb.context) if @CONF[:IRB_RC]
    @CONF[:MAIN_CONTEXT] = irb.context

    catch(:IRB_EXIT) do
      irb.eval_input
    end
  end
end

class PaizoDownloader
  attr_reader :username, :password, :agent, :download_path, :logged_in

  # create a new instance
  def initialize opts={}
    @baseurl=opts[:url] || "http://paizo.com/"
    @username=opts[:username] || ENV["PAIZO_USER"]
    @password=opts[:password]
    @log=opts[:log]
    @agent=opts[:agent]
    @download_path=opts[:dir] || opts[:download_path] || "#{ENV["HOME"]}/Dropbox/GnomePunters/Paizo"
    unless @agent
      @agent=Mechanize.new
    end
    unless @log.respond_to?(:info)
      @log=Logger.new(@log)
    end
    @agent.log = opts.has_key?(:agent_log) ? opts[:agent_log] : Logger.new("paizo.log")
    @agent.user_agent_alias = "Mac Safari"
    @agent.pluggable_parser.default=Mechanize::Download
    @logged_in=false

    @log.info "user=#{username}"
    @log.info "pass=#{"*" * password.length}"
    @log.info "useragent=#{@agent.user_agent}"

    FileUtils.mkdir_p(@download_path)

  end

  # make sure we're on the homepage
  def go_home
    @log.info "going to homepage #{@baseurl}"
    @agent.get(@baseurl)
    @log.info "received #{@agent.page.body.length} bytes"
  end

  # make sure we're on the downloads page
  def go_to_downloads
    self.login
    self.go_home
    @log.info "clicking 'My Downloads' link"
    @agent.page.link_with(:text => 'My Downloads').click
    @log.info "received #{@agent.page.body.length} bytes"
  end

  # log into the website
  def login
    if ! @logged_in
      self.go_home
      @log.info "clicking 'Sign In'"
      @agent.page.link_with(:text => 'Sign In').click
      @log.info "received #{@agent.page.body.length} bytes"

      unless f=@agent.page.form_with(:action => /\/signIn$/)
        @log.error "unable to find form with signIn action"
        exit 1
      end

      f.e=username
      f.p=password

      @log.info "submitting login form"
      @agent.submit(f)
      @log.info "received #{@agent.page.body.length} bytes"

      if @agent.page.link_with(:text => 'Sign In')
        @log.error "login failed; still have a 'Sign In' link"
        exit 1
      end

      @logged_in = true
    end
  end

  # get the timestamp from a <td><time datetime="...">...</time></td> structure
  def timestamp_from_td td
    if x=td.at('time')
      Time.iso8601(x['datetime'])
    else
      nil
    end
  end

  # force update the list of possible downloads
  def refresh_downloads
    self.go_to_downloads
    @log.info "fetching list of downloads"
    @downloads = Array.new
    @agent.page.search('tr.evenOdd').each_with_index do |download_row, idx|
      docname=download_row.at('a').text.sub(/^\s+/,'').sub(/\s+$/,'')
      publisher=download_row.previous
      while publisher['class'] =~ /evenOdd/
        publisher=publisher.previous
      end
      publisher=publisher.at('b').text.sub(/\s+$/,'').sub(/^\s+/,'').sub(/:\s+/,'/')
      date=Hash.new
      date[:downloaded] = timestamp_from_td(download_row.search('td')[2])
      date[:updated] = timestamp_from_td(download_row.search('td')[3])
      date[:added] = timestamp_from_td(download_row.search('td')[4])
      if date[:downloaded].nil?
        status=:never
      elsif date[:downloaded] > date[:updated]
        status=:old
      else
        status=:new
      end
      record = { :docname => docname, :publisher => publisher, :link => download_row.at('a'), :idx => idx, :row => download_row, :date => date, :status => status }
      @downloads.push record
    end
    @downloads
  end

  # return the list of possible downloads, refreshing if requested or none cached
  def downloads refresh=false
    if refresh or !@downloads
      refresh_downloads
    else
      @downloads
    end
  end

  # given a download or index into the downloads, attempt to save it
  def save download
    sleeptimes=[ 2, 4, 8, 10 ]
    download=Integer === download ? self.downloads[download] : download
    @log.info "starting a download of #{download[:docname]}"
    @agent.click(download[:link])
    link=nil
    (sleeptimes.length + 1).times do |nth_time|
      if nth_time == 0
        @log.info "clicking on download link for #{download[:docname]}"
      else
        @log.info "retry ##{nth_time} for the download link for #{download[:docname]}"
      end
      if link=@agent.page.link_with(:text => 'click here', :href => /^https:/)
        break
      else
        delay=sleeptimes.shift
        @log.info "waiting #{delay} seconds for download link to be available"
        sleep #{delay}
        @agent.click(download[:link])
      end
    end
    unless link
      @log.error "no download link after 10 seconds, aborting!"
      return 0
    end
    filename=link.href.sub(/.*\//,'')
    @log.info "downloading #{filename}"
    @agent.click(link)
    filename=@agent.page.filename
    @log.info "saving #{filename} into #{@download_path}/#{download[:publisher]}/#{download[:docname]}/"
    @agent.page.save("#{@download_path}/#{download[:publisher]}/#{download[:docname]}/#{filename}")
    self.refresh_downloads
    true
  end

end

# parse command line options

username=ENV["PAIZO_USER"]
password=ENV["PAIZO_PASS"]

if ARGV.length >= 2
  username=ARGV.shift
  password=ARGV.shift
elsif ARGV.length == 1
  if username.nil?
    username=ARGV.shift
  else
    password=ARGV.shift
  end
end

if password.nil? and username =~ /:/
  username, password = username.split(/:/)
end

if username.nil?
  username = ask("Enter your Paizo username: ")
end

while password.nil? or password.length == 0
  password = ask("Enter your Paizo password: ") { |q| q.echo = false }
end

log.info "making new PaizoDownloader object"
paizo=PaizoDownloader.new({ :username => username, :password => password, :log => log })

log.info "found #{paizo.downloads.length} download links"

paizo.downloads.each do |download| 
  d=download[:date]
  msg=""
  puts "#{download[:idx]}: #{download[:docname]}: #{msg}"
end

IRB.start_session(binding)


