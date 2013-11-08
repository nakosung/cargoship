seaport = require 'zk-seaport'
net = require 'net'
os = require 'os'
fs = require 'fs'
_ = require 'underscore'
MuxDemux = require 'mux-demux'
es = require 'event-stream'
events = require 'events'
{argv} = require 'optimist'

localIp = ->
	result = []

	for k,v of os.networkInterfaces()
		for i in v
			if not i.internal and i.family == 'IPv4'
				result.push i.address

	result[0]

lets_sail = (opts,handler) ->
	ports = seaport process.env
	server = net.createServer (conn) ->
		conn.setEncoding 'utf-8'
		conn.once 'error', ->
			conn.end()			
		handler conn

	port = null
	server.on 'listening', ->
		console.log "bound to port #{port}"
		opts.advertise ?= yes
		if opts.advertise
			ad = host:opts.host or localIp(), port:port		
			# console.log "advertise", ad
			ports.register opts.role, ad
	bind = (_port) ->
		# console.log "binding to port #{_port}"
		port = _port
		server.listen port
		server.once 'error', (e) ->
			if e.code == 'EADDRINUSE'
				try_another_port()
	try_another_port = null

	if opts.port?
		try_another_port = ->
			throw new Error("Address in use")
		bind(opts.port)
	else
		begin = opts.port_begin or 40000
		end = opts.port_end or (begin + 10000)
		cands = _.shuffle(_.range(begin,end))
		
		try_another_port = ->
			throw new Error("No address to use") unless cands.length
			p = cands.pop()
			bind p

		try_another_port()	
	

cargoship = module.exports = (args...) ->
	cargoship.new args...	

cargoship.static = (folder) ->
	(m) ->
		url = m.url		
		i = url.indexOf('?')
		url = url.substr(0,i) if i >= 0
		
		s = fs.createReadStream folder + '/' + url
		s.pipe(m)
		s.once 'error', -> m.end()
		s.once 'end', -> m.end()

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

cargoship.auth = (m,next) ->
	user = m.meta.user
	return m.end() unless user?

	m.user = user
	return m.end() unless user._id?

	next m
cargoship.auth.preuse = (ship) ->
	ship.use cargoship.metaParser

cargoship.metameta = (m,next) ->
	meta = m.meta.meta
	if meta?
		try
			m.metameta = JSON.parse meta
		catch e
	next m	
cargoship.metameta.preuse = (ship) ->
	ship.use cargoship.metaParser

cargoship.json = (fallback) ->
	(m,next) ->
		try
			m.json = JSON.parse m.meta.meta
			next m
		catch e
			m.json = fallback m.meta.meta
			next m

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

	__config = {}
	__locked = false	
	fn.config = (k,v) ->
		if v?
			throw new Error("cargoship config locked") if __locked
			__config[k] = v
		else
			__config[k]
	fn.config.lock = ->
		__locked = true

	_.extend fn,
		use : (x) ->		
			get_signature = (x) ->
				x?.signature or String(x)
			return if _.contains _.map(services,get_signature), get_signature(x)
			x.preuse?(@)
			services.push x		

		launch : (role,_argv) ->			
			_argv = _.extend (_.extend {}, argv), _argv or {}
			opts = 
				role : role
				host : _argv.ip
				port : _argv.port
				advertise : _argv.advertise			
			
			[name,version] = role.split('@')

			fn.user = 
				server : true
				id : role	
				name : name
				version : version	

			fn.emit 'launch'

			lets_sail opts, (c) ->
				mx = MuxDemux (m) ->
					m.mx = mx
					m.once 'end', -> delete m.mx
					m.once 'error', ->
						console.error 'mux stream got error'
						m.end()
					fn m, (m) ->
						console.error 'unhandled stream'
						m.end()										
				es.pipeline(mx,c,mx).once 'error', ->
					console.error 'got error!'
					c.end()
				mx.upstream = c
				fn.emit 'connect', mx				
		
	_.extend fn, new events.EventEmitter()

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
