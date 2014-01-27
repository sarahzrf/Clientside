require 'faye/websocket'

class Clientside
	RPATH = '/__clientside__/'

	@@expected_sockets = {}
	@@sockets = {}

	def initialize(app)
		@app = app
	end

	def call(env)
		if Faye::WebSocket.websocket? env and env['REQUEST_PATH'].start_with? RPATH
			ws = Faye::WebSocket.new(env)

			ws.on :open do |event|
				env['REQUEST_PATH'] =~ %r(\A#{RPATH}(.+)\Z)
				oid = $1
				key = [env['REMOTE_ADDR'], oid]
				obj = @@expected_sockets.delete(key)
				unless obj.nil?
					@@sockets[ws] = obj
				else
					ws.close
				end
			end

			ws.on :message do |event|
				# TODO: implement this
			end

			ws.on :close do |event|
				@@sockets.delete ws
				ws = nil
			end

			ws.rack_response
		else
			@app.(env)
		end
	end
end

# vim:tabstop=2 shiftwidth=2 noexpandtab:

