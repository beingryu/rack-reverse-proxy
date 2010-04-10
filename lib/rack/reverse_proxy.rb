require 'net/http'

module Rack
  class ReverseProxy
    def initialize(app = nil, &b)
      @app = app || lambda { [404, [], []] }
      @paths = {}
      instance_eval &b if block_given?
    end

    def call(env)
      rackreq = Rack::Request.new(env)
      matcher, url = get_matcher_and_url rackreq.fullpath
      return @app.call(env) if matcher.nil?

      path = rackreq.fullpath
      match = case matcher
              when String
                path.match(/^#{matcher}/)
              when Regexp
                path.match(matcher)
              end
      uri = case url 
            when /\$\d/
              match.to_a.each_with_index { |m, i| url.gsub!("$#{i.to_s}", m) }
              URI(url)
            else
              URI.join(url, path)
            end
 
       headers = Rack::Utils::HeaderHash.new
       env.each { |key, value|
         if key =~ /HTTP_(.*)/
           headers[$1] = value
         end
       }
 
       res = Net::HTTP.start(uri.host, uri.port) { |http|
         m = rackreq.request_method
         case m
         when "GET", "HEAD", "DELETE", "OPTIONS", "TRACE"
           req = Net::HTTP.const_get(m.capitalize).new(uri.path, headers)
         when "PUT", "POST"
           req = Net::HTTP.const_get(m.capitalize).new(uri.path, headers)
           req.body_stream = rackreq.body
         else
           raise "method not supported: #{method}"
         end
 
         http.request(req)
       }
 
       [res.code, Rack::Utils::HeaderHash.new(res.to_hash), [res.body]]
    end
    
    private

    def get_matcher_and_url path
      matches = @paths.select do |matcher, url|
        case matcher
        when String
          path =~ /^#{matcher}/
        when Regexp
          path =~ matcher
        end
      end

      if matches.length < 1
        nil
      elsif matches.length > 1
        raise AmbiguousProxyMatch
      else
        matches.first.map{|a| a.dup}
      end
    end

    def reverse_proxy matcher, url
      @paths.merge!(matcher => url)
    end
  end

  class AmbiguousProxyMatch < Exception
  end

end
