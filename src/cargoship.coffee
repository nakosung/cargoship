seaport = require 'seaport'
net = require 'net'
os = require 'os'

localIp = ->
	result = []

	for k,v of os.networkInterfaces()
		for i in v
			if not i.internal and i.family == 'IPv4'
				result.push i.address

	result[0]

old_fn = (seaportloc,role,handler) ->
	ports = seaport.connect seaportloc...
	server = net.createServer (conn) ->
		conn.setEncoding 'utf-8'		
		conn.on 'error', ->
			conn.end()
		handler conn

	server.listen ports.register role, host:localIp()

new_fn = (opts,handler) ->
	ports = seaport.connect opts.address...
	server = net.createServer (conn) ->
		conn.setEncoding 'utf-8'
		conn.on 'error', ->
			conn.end()			
		handler conn

	port = ports.register opts.role, host:opts.host or localIp(), port:opts.port	
	server.listen opts.port or port

module.exports = (args...) ->
	if args.length == 3
		old_fn args...
	else
		new_fn args...