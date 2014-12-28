#!/usr/bin/env ruby
#
# Crappy media downloader for https://www.usenix.org
#

require 'mechanize'

url = "https://www.usenix.org/conferences/multimedia"
agent = Mechanize.new
agent.user_agent_alias = 'Mac Safari'
agent.pluggable_parser.default = Mechanize::Download

def save_file(url, path, title)
  puts "Saving file #{path}"

  dir = File.dirname(path)
  ext = File.extname(path)
  fname = File.basename(path, ext)
  FileUtils.mkdir_p(dir)

  nfo_file = File.join(dir, "#{fname}.nfo")

  # save the URL from where the file was downloaded
  unless File.exist?(nfo_file)
    File.open(nfo_file, 'w') do |f|
      f.puts "<movie>\n<title>\n#{title}\n</title>\n</movie>"
      f.puts url
    end
  end

  `curl -# -C - --retry 2 -o #{path} #{url}`
end

def fetch_video(agent, url)
  presentations = agent.get(url).links.find_all do |l|
    l.uri.to_s =~ /presentation/
  end

  presentations.each do |p|
    page = agent.get(p.uri.to_s)
    video_name= page.title.gsub(/[^0-9A-Za-z.\-]/, '_') || 'unknown_title'
    conference = page.uri.path.split('/')[2] || 'unknown'

    page.links.each do |l|
      url = l.uri.to_s
      next unless url =~ /(avi|mp4|ogg|mp3|mov)$/

      save_file url, "#{conference}/#{video_name}#{File.extname(url)}", page.title
    end
  end
end

pages = [url]
1.upto(5) { |i| pages << "#{url}?page=#{i}" }

pages.each { |page| fetch_video(agent, page) }