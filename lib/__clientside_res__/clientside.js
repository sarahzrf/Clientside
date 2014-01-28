var makeClientsideProxy = (function() {
	var reqId = 0;

	var remoteInvoke = function(socket, obj, method, args) {
		var request = {"receiver": obj, "method": method, "arguments": args};
		var id = request.id = ++reqId;
		var promise = new Promise(function(resolve, reject) {
			socket.pending[id] = [resolve, reject];
		});
		socket.send(JSON.stringify(request));
		return promise;
	}

	var proxyMaker = function(socket, obj) {
		var proto = {};
		var proxy = Object.create(proto);
		proxy.__clientside__ = true;
		proxy.__clientside_id__ = obj.__clientside_id__;
		for (var i = 0; i < obj.methods.length; i++) {
			var methodName = obj.methods[i];
			proto[methodName] = (function(closableName) {
				return function() {
					var args = Array.slice(arguments);
					return remoteInvoke(socket, proxy, closableName, args);
				};
			})(methodName);
		}
		return proxy;
	}

	return proxyMaker;
})();

var makeClientsideSocket = (function() {
	var proxify = function(socket, obj) {
		if (obj instanceof Object) {
			for (key in obj) {
				if (obj[key].__clientside__) {
					obj[key] = makeClientsideProxy(socket, obj[key]);
				}
			}
		}
		else if (obj instanceof Array) {
			for (var i = 0; i < obj.length; i++) {
				if (obj[i].__clientside__) {
					obj[i] = makeClientsideProxy(socket, obj[i]);
				}
			}
		}
	};

	var socketMaker = function(uri) {
		var socket = new WebSocket(uri);
		socket.pending = {};
		socket.onmessage = function(event) {
			var response = JSON.parse(event.data);
			var callbacks = socket.pending[response.id];
			if (!callbacks) {
				return;
			}
			else if (response.status == 'success') {
				proxify(socket, response);
				callbacks[0](response.result); // resolve
			}
			else {
				callbacks[1](); // reject
			}
		};
		return socket;
	}

	return socketMaker;
})();

