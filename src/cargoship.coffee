seaport = require 'seaport'
net = require 'net'
os = require 'os'

module.exports = (seaportloc,role,handler) ->
	localIp = ->
		result = []

		for k,v of os.networkInterfaces()
			for i in v
				if not i.internal and i.family == 'IPv4'
					result.push i.address

		result[0]

	ports = seaport.connect seaportloc...
	server = net.createServer (conn) ->
		conn.setEncoding 'utf-8'		
		handler conn

	server.listen ports.register role, host:localIp()
