require 'json'
require 'faye/websocket'
require 'rack/static'
require 'securerandom'

class Clientside
  module Accessible
    class << self
      attr_accessor :cur_os

      def included(base)
        base.singleton_class.class_eval do
          attr_reader :js_allowed

          def js_allow(*args)
            (@js_allowed ||= []).concat args
          end
        end
      end

      def reinflate(json, os)
        case json
        when Hash
          if json[:__clientside__]
            os.fetch json[:__clientside_id__]
          else
            Hash[json.map {|k, v| [k, reinflate(v, os)]}]
          end
        when Array
          json.map {|v| reinflate(v, os)}
        else
          json
        end
      end
    end

    def to_json(*args)
      name = self.class.name
      methods = self.class.js_allowed
      h = {__clientside__: true, __clientside_id__: object_id, methods: methods}
      h.to_json *args
    end
  end

  class NoResMiddleware
    RPATH = '/__clientside_sock__/'
    MAX_OBJECTS = 256

    @@pending_sockets = {}
    @@sockets = {}

    def initialize(app)
      @app = app
    end

    def register_obj(ws, obj)
      @@sockets[ws][obj.object_id] = obj
    end

    def handle_message(cmd, ws)
      raise unless cmd[:receiver].kind_of? Clientside::Accessible
      allowed = cmd[:receiver].class.js_allowed
      raise unless allowed.include? cmd[:method].to_sym

      result = cmd[:receiver].send cmd[:method], *cmd[:arguments]
      o_tj_source = JSON::Ext::Generator::GeneratorMethods::Object
      result = nil if result.method(:to_json).owner.equal? o_tj_source

      if result.kind_of? Accessible
        unless @@sockets[ws].length >= MAX_OBJECTS
          register_obj ws, result 
        else
          raise
        end
      end
      ws.send JSON.dump({status: 'success', id: cmd[:id], result: result})
    end

    def call(env)
      if Faye::WebSocket.websocket? env and env['REQUEST_PATH'].start_with? RPATH
        env['REQUEST_PATH'] =~ %r(\A#{RPATH}(.+)\Z)
        cid = $1
        objs = @@pending_sockets.delete(cid)

        unless objs.nil?
          ws = Faye::WebSocket.new(env)
          @@sockets[ws] = objs
        else
          return @app.call env
        end

        ws.on :message do |event|
          begin
            cmd = JSON.parse event.data, symbolize_names: true
            cmd = Clientside::Accessible.reinflate cmd, @@sockets[ws]
            handle_message cmd, ws
          rescue RuntimeError, KeyError => e
            ws.send JSON.dump({status: 'error', id: cmd[:id]})
          end
        end

        ws.on :close do |event|
          @@sockets.delete ws
          ws = nil
        end

        ws.rack_response
      else
        @app.call env
      end
    end

    def self.add_pending(objs)
      objs = Hash[objs.map {|o| [o.object_id, o]}]
      cid = SecureRandom.hex
      @@pending_sockets[cid] = objs
      cid
    end
  end

  class Middleware < NoResMiddleware
    def initialize(*args)
      super
      dir = File.dirname(__FILE__)
      @app = Rack::Static.new(@app, urls: ['/__clientside_res__'], root: dir)
    end
  end

  def self.embed(objs)
    objs.each do |var, obj|
      raise ArgumentError, "invalid js var name" unless var =~ /\A[a-zA-Z_]\w*\Z/
    end
    cid = Clientside::Middleware.add_pending objs.values
    sock_var = '$__clientside_socket__'
    js = ""
    js << %Q(<script src="/__clientside_res__/promise.min.js"></script>\n)
    js << %Q(<script src="/__clientside_res__/clientside.js"></script>\n)
    js << %Q(<script>\n)
    objs.each do |var, obj|
      js << %Q(var #{var};\n)
    end
    js << %Q(var #{sock_var} = makeClientsideSocket("#{cid}");\n)
    js << %Q(#{sock_var}.onopen = function() {\n)
    objs.each do |var, obj|
      json = JSON.dump obj
      js << %Q(    #{var} = makeClientsideProxy(#{sock_var}, #{json});\n)
    end
    js << %Q(};\n)
    js << %Q(</script>\n)
  end
end

# vim:tabstop=2 shiftwidth=2 noexpandtab:

