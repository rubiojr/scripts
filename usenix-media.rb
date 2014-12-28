#!/usr/bin/env ruby
#
# Crappy media downloader for https://www.usenix.org
#

require 'mechanize'
require 'uri'
require 'net/http'
require 'progressbar'

url = "https://www.usenix.org/conferences/multimedia"
agent = Mechanize.new
agent.user_agent_alias = 'Mac Safari'
agent.pluggable_parser.default = Mechanize::Download

def save_file(url, path)
  puts "Saving file #{path}"
  FileUtils.mkdir_p(File.dirname(path))
  link_file = path + '.link'

  # save the URL from where the file was downloaded
  unless File.exist?(link_file)
    File.open(path + '.link', 'w') { |f| f.puts url }
  end

  `curl -# -C - --retry 2 -o #{path} #{url}`
end

def fetch_video(agent, url)
  puts "Fetching video form page #{url}"

  presentations = agent.get(url).links.find_all do |l|
    l.uri.to_s =~ /presentation/
  end

  presentations.each do |p|
    page = agent.get(p.uri.to_s)
    video_name= page.title.gsub!(/[^0-9A-Za-z.\-]/, '_') || 'unknown_title'
    conference = page.uri.path.split('/')[2] || 'unknown'

    page.links.each do |l|
      url = l.uri.to_s
      next unless url =~ /(avi|mp4|ogg|mp3|mov)$/

      save_file url, "#{conference}/#{video_name}#{File.extname(url)}"
    end
  end
end

pages = [url]
1.upto(5) { |i| pages << "#{url}?page=#{i}" }

pages.each { |page| fetch_video(agent, page) }