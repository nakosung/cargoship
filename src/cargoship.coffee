seaport = require 'seaport'
net = require 'net'
os = require 'os'
fs = require 'fs'
_ = require 'underscore'
MuxDemux = require 'mux-demux'
es = require 'event-stream'

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

cargoship = module.exports = (args...) ->
	if args.length == 0
		cargoship.new args...
	else if args.length == 3
		old_fn args...
	else
		new_fn args...

cargoship.static = (folder) ->
	(m) ->
		url = m.url		
		i = url.indexOf('?')
		url = url.substr(0,i) if i >= 0
		
		s = fs.createReadStream folder + '/' + url
		s.pipe(m)
		s.on 'error', -> m.end()
		s.on 'end', -> m.end()

cargoship.metaParser = (m,next) ->
	m.meta = JSON.parse m.meta	
	next m

cargoship.http = (m,next) ->
	meta = m.meta	
	try
		doc = JSON.parse meta.meta
		if doc.http?
			m.url = doc.http.url
			m.method = doc.http.method		
	catch e

	next m

cargoship.http.preuse = (ship) ->
	ship.use cargoship.metaParser

cargoship.new = ->
	services = []
	fn = (m,user_next) ->	
		shot = (i) ->			
			if i == services.length
				(m,next) -> user_next m, ->
			else
				(m,next) ->
					services[i] m, shot(i+1)

		f = shot 0	
		f(m)

	_.extend fn,
		use : (x) ->			
			return if _.contains services, x
			x.preuse?(@)
			services.push x		
		launch : (role,loc...) ->
			cargoship loc, role, (c) ->
				mx = MuxDemux (m) ->
					m.on 'error', ->
						console.error 'mux stream got error'
						m.end()
					fn m, (m) ->
						console.error 'unhandled stream'
						m.end()										
				es.pipeline(mx,c,mx).on 'error', ->
					console.error 'got error!'
					c.end()

	['get','post','delete','all'].forEach (v) ->
		V = v.toUpperCase()		

		test_method = (m) ->
			m.method == V
		
		if v == 'all' 
			test_method = (m) -> m.method?

		fn[v] = (pattern,action) ->
			@use cargoship.http
			services.push (m,next) ->
				if test_method(m) and pattern.test(m.url)
					action m
				else
					next m	
	fn