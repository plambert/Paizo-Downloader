#!/usr/bin/env ruby

require 'rubygems'
require 'mechanize'
require 'highline/import'
require 'logger'
require 'irb'

baseurl="http://paizo.com/"

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

#class PaizoDownloadParser << Mechanize::Download
  #def initialize uri = nil, response = nil, body = nil, code = nil
    #super uri, response, body, code
  #end
#end



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

log.info "user=#{username} pass=#{"*" * password.length}"

agent=Mechanize.new

agent.log = Logger.new "mech.log"
agent.user_agent_alias = "Mac Safari"
agent.pluggable_parser.default=Mechanize::Download

log.info "getting #{baseurl}"
agent.get(baseurl)
log.info "received #{agent.page.body.length} bytes"

log.info "clicking 'Sign In'"
agent.page.link_with(:text => 'Sign In').click
log.info "received #{agent.page.body.length} bytes"

unless f=agent.page.form_with(:action => /\/signIn$/)
  log.error "unable to find form with signIn action"
  exit 1
end

f.e=username
f.p=password

log.info "submitting login form"
agent.submit(f)
log.info "received #{agent.page.body.length} bytes"

if agent.page.link_with(:text => 'Sign In')
  log.error "login failed; still have a 'Sign In' link"
  exit 1
end

log.info "clicking 'My Downloads' link"
agent.page.link_with(:text => 'My Downloads').click
log.info "received #{agent.page.body.length} bytes"

def download_file(agent,log,download)
  log.info "starting a download"
  docname=download.at('a').text.sub(/^\s+/,'').sub(/\s+$/,'')
  publisher=download.previous
  while publisher['class'] =~ /evenOdd/
    publisher=publisher.previous
  end
  publisher=publisher.at('b').text.sub(/\s+$/,'').sub(/^\s+/,'').sub(/:\s+/,'/')
  agent.click(download.at('a'))
  log.info "clicking on download link for #{docname}"
  link=agent.page.link_with(:text => 'click here', :href => /^https:/)
  if ! link
    log.info "waiting 10 seconds for download link to be available"
    sleep 10
    agent.back
    agent.click(download.at('a'))
    link=agent.page.link_with(:text => 'click here', :href => /^https:/)
    if ! link
      log.error "no download link after 10 seconds, aborting!"
      return 0
    end
  end
  filename=link.href.sub(/.*\//,'')
  log.info "downloading #{filename}"
  agent.click(link)
  log.info "saving #{filename} into Paizo/#{publisher}/#{docname}/"
  agent.page.save("Paizo/#{publisher}/#{docname}/#{agent.page.filename}")
  agent.back
end

def get_downloads(agent)
  agent.page.search('tr.evenOdd')
end

FileUtils.mkdir_p('Paizo')

downloads=get_downloads(agent)
log.info "found #{downloads.length} download links"

download_file(agent,log,downloads[1])

IRB.start_session(binding)

