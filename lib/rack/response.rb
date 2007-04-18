require 'rack/request'
require 'rack/utils'

module Rack
  # Rack::Response provides a convenient interface to create a Rack
  # response.
  #
  # It allows setting of headers and cookies, and provides useful
  # defaults (a OK response containing HTML).
  #
  # You can use Response#write to iteratively generate your response,
  # but note that this is buffered by Rack::Response until you call
  # +finish+.  +finish+ however can take a block inside which calls to
  # +write+ are syncronous with the Rack response.
  #
  # Your application's +call+ should end returning Response#finish.

  class Response
    def initialize(body=[], status=200, header={}, &block)
      @status = status
      @header = Utils::HeaderHash.new({"Content-Type" => "text/html"}.
                                      merge(header))

      @writer = lambda { |x| @body << x }
      @block = nil

      @body = []

      if body.respond_to? :to_str
        write body.to_str
      elsif body.respond_to?(:each)
        body.each { |part|
          write part.to_s
        }
      else
        raise TypeError, "stringable or iterable required"
      end

      yield self  if block_given?
    end

    attr_reader :header
    attr_accessor :status, :body

    def [](key)
      header[key]
    end

    def []=(key, value)
      header[key] = value
    end

    def set_cookie(key, value)
      case value
      when Hash
        domain  = "; domain="  + value[:domain]    if value[:domain]
        path    = "; path="    + value[:path]      if value[:path]
        expires = "; expires=" + value[:expires].clone.gmtime.
          strftime("%a, %d %b %Y %H:%M:%S GMT")    if value[:expires]
        value = value[:value]
      end
      value = [value]  unless Array === value
      cookie = Utils.escape(key) + "=" +
        value.map { |v| Utils.escape v }.join("&") +
        "#{domain}#{path}#{expires}"

      case self["Set-Cookie"]
      when Array
        self["Set-Cookie"] << cookie
      when String
        self["Set-Cookie"] = [self["Set-Cookie"], cookie]
      when nil
        self["Set-Cookie"] = cookie
      end
    end

    def delete_cookie(key, value={})
      unless Array === self["Set-Cookie"]
        self["Set-Cookie"] = [self["Set-Cookie"]]
      end

      self["Set-Cookie"].reject! { |cookie|
        cookie =~ /\A#{Utils.escape(key)}=/
      }

      set_cookie(key,
                 {:value => '', :path => nil, :domain => nil,
                   :expires => Time.at(0) }.merge(value))
    end


    def finish(&block)
      @block = block

      if [201, 204, 304].include?(status.to_i)
        header.delete "Content-Type"
        [status.to_i, header.to_hash, []]
      else
        [status.to_i, header.to_hash, self]
      end
    end
    alias to_a finish           # For *response

    def each(&callback)
      @body.each(&callback)
      @writer = callback
      @block.call(self)  if @block
    end

    def write(str)
      @writer.call str.to_s
      str
    end

    def empty?
      @block == nil && @body.empty?
    end
  end
end
