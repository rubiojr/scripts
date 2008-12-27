require 'net/http'
require 'rubygems'
require 'thin'
require 'rack'
require 'delegate'
require 'util'
require 'uri'

#
# Initial idea taken from http://github.com/mikehale/rat-hole
#
class ForceField

  def initialize(host=nil)
    @host = host
    @request_callback = nil
    @response_callback = nil
  end

  def on_request(&block)
    if block
      @request_callback = block
    else
      @request_callback.call @req
    end
  end

  def on_response(&block)
    if block
      @response_callback = block
    else
      @response_callback.call @resp if @response_callback
    end
  end

  def call(env)
    # we don't want to handle compressed stuff for now
    env.delete('HTTP_ACCEPT_ENCODING')
    @req = Rack::Request.new(env)
    target = @host || @req.host
    on_request
    user_headers = request_headers(@req.env)
    uri = URI.parse(env['REQUEST_URI'])
    upath = "#{uri.path}?#{(uri.query || '')}"

    Net::HTTP.start(target) do |http|
      if @req.get?
        response = http.get(upath, user_headers)
      elsif @req.post?
        post = Net::HTTP::Post.new(upath, user_headers)
        post.form_data = @req.POST
        response = http.request(post)
      end

      code = response.code.to_i
      headers = response.to_hash
      body = response.body || ''
      on_response
      @resp = Rack::Response.new(body, code)
      @resp.finish
    end
  end

  def request_headers(env)
    env.select{|k,v| k =~ /^HTTP/}.inject({}) do |h, e|
      k,v = e
      h.merge(k.split('_')[1..-1].join('-').to_camel_case => v)
    end
  end

  def start
    Rack::Handler::Mongrel.run(self, {:Host => 'localhost', :Port => 5001})
  end
end

ff = ForceField.new
ff.on_request do |req|
  if req.get?
    puts "req: GET '#{req.fullpath}' [#{req.host}]"
  elsif req.post?
    puts "req: POST #{req.fullpath} params: #{req.params.inspect} [#{req.host}]"
  else
    puts 'req: UNKNOWN'
  end
end
ff.start
