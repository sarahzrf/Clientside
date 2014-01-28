require 'json'
require 'faye/websocket'
require 'rack/static'
require 'securerandom'
require 'ostruct'

module Clientside
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
      h = {__clientside__: true, __clientside_id__: object_id,
           methods: methods}
      h.to_json *args
    end
  end

  class NoResMiddleware
    RPATH = '/__clientside_sock__/'
    MAX_OBJECTS = 256
    PENDING_TTL = 5 * 60

    @@pending_sockets = {}
    @@pending_expiries = []
    @@sockets = {}

    def initialize(app)
      @app = app
    end

    def register_obj(ws, obj)
      @@sockets[ws][obj.object_id] = obj
    end

    def handle_message(cmd, ws)
      can_receive = cmd.receiver.kind_of? Accessible
      raise "receiver is not js-accessible" unless can_receive
      is_name = cmd.method_.respond_to? :to_sym
      raise "not a method name: #{cmd.method_}" unless is_name
      allowed = cmd.receiver.class.js_allowed.include? cmd.method_.to_sym
      raise "unknown method: #{cmd.method_}" unless allowed

      begin
        result = cmd.receiver.send cmd.method_, *cmd.arguments
      rescue ArgumentError => e
        raise e.message
      end
      o_tj_source = JSON::Ext::Generator::GeneratorMethods::Object
      result = nil if result.method(:to_json).owner.equal? o_tj_source

      if result.kind_of? Accessible
        unless @@sockets[ws].length >= MAX_OBJECTS
          register_obj ws, result 
        else
          raise "too many objects allocated"
        end
      end
      ws.send JSON.dump({status: 'success', id: cmd.id, result: result})
    end

    def call(env)
      is_websocket = Faye::WebSocket.websocket? env
      for_us = env['REQUEST_PATH'].start_with? RPATH
      if is_websocket and for_us
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
            needed = [:receiver, :method_, :arguments, :id]
            unless needed.all? {|k| cmd.key? k}
              if cmd.key? :id
                ws.send JSON.dump({status: 'error',
                                   message: 'invalid request', id: cmd[:id]})
              end
              next
            end
            cmd = Accessible.reinflate cmd, @@sockets[ws]
            cmd = OpenStruct.new cmd
            handle_message cmd, ws
          rescue JSON::ParserError
          rescue KeyError => e
            e.message =~ /\Akey not found: (.+)\Z/
            missing_id = $1
            message = "unknown object id: #{missing_id}"
            ws.send JSON.dump({status: 'error',
                               message: message, id: cmd.id})
          rescue RuntimeError => e
            ws.send JSON.dump({status: 'error',
                               message: e.message, id: cmd.id})
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
      @@pending_expiries << [cid, Time.now + PENDING_TTL]
      until @@pending_expiries.first[1] > Time.now
        ecid, _ = @@pending_expiries.shift
        @@pending_sockets.delete ecid
      end
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
      raise ArgumentError, "invalid var name" unless var =~ /\A[a-zA-Z_]\w*\Z/
    end
    cid = Middleware.add_pending objs.values
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

# vim:tabstop=2 shiftwidth=2 expandtab:

