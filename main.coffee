class PrecisePath extends g.RPath
	@rname = 'Precise path'
	@rdescription = "This path offers precise controls, one can modify points along with their handles and their type."
	@iconURL = 'static/images/icons/inverted/editCurve.png'
	@iconAlt = 'edit curve'

	@hitOptions =
		segments: true
		stroke: true
		fill: true
		selected: true
		curves: true
		handles: true
		tolerance: 5

	@secureStep = 25
	@polygonMode = true

	@parameters: ()->

		parameters = super()

		if @polygonMode
			parameters['General'].polygonMode =
				type: 'checkbox'
				label: 'Polygon mode'
				default: g.polygonMode
				onChange: (value)-> g.polygonMode = value

		parameters['Edit curve'] =
			smooth:
				type: 'checkbox'
				label: 'Smooth'
				default: false
			pointType:
				type: 'dropdown'
				label: 'Point type'
				values: ['smooth', 'corner', 'point']
				default: 'smooth'
				addController: true
				onChange: (value)-> item.modifyPointTypeCommand?(value) for item in g.selectedItems; return
			deletePoint:
				type: 'button'
				label: 'Delete point'
				default: ()-> item.deletePointCommand?() for item in g.selectedItems; return
			simplify:
				type: 'button'
				label: 'Simplify'
				default: ()->
					for item in g.selectedItems
						item.controlPath?.simplify()
						item.draw()
						item.update()
					return

		return parameters

	# overload {RPath#constructor}
	constructor: (@date=null, @data=null, @pk=null, points=null, @lock) ->
		super(@date, @data, @pk, points, @lock)
		if @constructor.polygonMode then @data.polygonMode = g.polygonMode
		@rotation = @data.rotation = 0
		return

	# redefine {RPath#loadPath}
	# load control path from @data.points and check if *points* fit to the created control path
	loadPath: (points)->
		# load control path from @data.points
		@initializeControlPath(g.posOnPlanetToProject(@data.points[0], @data.planet))
		for point, i in @data.points by 4
			if i>0 then @controlPath.add(g.posOnPlanetToProject(point, @data.planet))
			@controlPath.lastSegment.handleIn = new Point(@data.points[i+1])
			@controlPath.lastSegment.handleOut = new Point(@data.points[i+2])
			@controlPath.lastSegment.rtype = @data.points[i+3]
		if points.length == 2 then @controlPath.add(points[1])

		@finish(true)

		if @data?.animate or g.selectedToolNeedsDrawings()	# only draw if animated thanks to rasterization
			@draw()

		time = Date.now()

		# check if points fit to the newly created control path:
		# - flatten a copy of the control path, as it was flattened when the path was saved
		# - check if *points* correspond to the points on this flattened path
		flattenedPath = @controlPath.copyTo(project)
		flattenedPath.flatten(@constructor.secureStep)
		distanceMax = @constructor.secureDistance*@constructor.secureDistance

		# only check 10 random points to speed up security check
		for i in [1 .. 10]
			index = Math.floor(Math.random()*points.length)
			recordedPoint = new Point(points[index])
			resultingPoint = flattenedPath.segments[index].point
			if recordedPoint.getDistance(resultingPoint, true)>distanceMax
				# @remove()
				flattenedPath.strokeColor = 'red'
				view.center = flattenedPath.bounds.center
				console.log "Error: invalid path"
				return

		flattenedPath.remove()
		console.log "Time to secure the path: " + ((Date.now()-time)/1000) + " sec."
		return

	# redefine hit test to test not only on the selection rectangle, but also on the control path
	# @param point [Point] the point to test
	# @param hitOptions [Object] the [paper hit test options](http://paperjs.org/reference/item/#hittest-point)
	hitTest: (point, hitOptions)->
		if @speedGroup?.visible then hitResult = @handleGroup?.hitTest(point)
		hitResult ?= super(point, hitOptions)
		hitResult ?= @controlPath.hitTest(point, hitOptions)
		return hitResult

	# initialize drawing
	# @param createCanvas [Boolean] (optional, default to true) whether to create a child canavs *@canvasRaster*
	initializeDrawing: (createCanvas=false)->
		@data.step ?= 20 	# developers do not need to put @data.step in the parameters, but there must be a default value
		@drawingOffset = 0
		super(createCanvas)
		return

	# default beginDraw function, will be redefined by children PrecisePath
	# @param redrawing [Boolean] (optional) whether the path is being redrawn or the user draws the path (the path is being loaded/updated or the user is drawing it with the mouse)

	beginDraw: (redrawing=false)->
		@initializeDrawing(false)
		@path = @addPath()
		@path.segments = @controlPath.segments
		@path.selected = false
		@path.strokeCap = 'round'
		return

	# default updateDraw function, will be redefined by children PrecisePath
	# @param offset [Number] the offset along the control path to begin drawing
	# @param step [Boolean] whether it is a key step or not (we must draw something special or not)
	updateDraw: (offset, step)->
		@path.segments = @controlPath.segments
		@path.selected = false
		return

	# default endDraw function, will be redefined by children PrecisePath
	# @param redrawing [Boolean] (optional) whether the path is being redrawn or the user draws the path (the path is being loaded/updated or the user is drawing it with the mouse)
	endDraw: (redrawing=false)->
		@path.segments = @controlPath.segments
		@path.selected = false
		return

	# continue drawing the path along the control path if necessary:
	# - the drawing is performed every *@data.step* along the control path
	# - each time the user adds a point to the control path (either by moving the mouse in normal mode, or by clicking in polygon mode)
	#   *checkUpdateDrawing* check by how long the control path was extended, and calls @updateDraw() if some draw step must be performed
	# called when creating the path (by @updateCreate() and @finish()) and in @draw()
	# @param segment [Paper Segment] the segment on the control path where we want to updateDraw
	# @param redrawing [Boolean] (optional) whether the path is being redrawn or the user draws the path (the path is being loaded/updated or the user is drawing it with the mouse)

	checkUpdateDrawing: (segment, redrawing=true)->
		step = @data.step
		controlPathOffset = segment.location.offset

		while @drawingOffset+step<controlPathOffset
			@drawingOffset += step
			@updateDraw(@drawingOffset, true, redrawing)

		if @drawingOffset+step>controlPathOffset 	# we can not make a step between drawingOffset and the controlPathOffset
			@updateDraw(controlPathOffset, false, redrawing)

		return

	# initialize the main group and the control path
	# @param point [Point] the first point of the path
	initializeControlPath: (point)->
		@addControlPath()
		@controlPath.add(point)
		@rectangle = @controlPath.bounds
		return

	# redefine {RPath#beginCreate}
	# begin create action:
	# initialize the control path and draw begin
	# called when user press mouse down, or on loading
	# @param point [Point] the point to add
	# @param event [Event] the mouse event
	beginCreate: (point, event)->
		super()

		if not @data.polygonMode 				# in normal mode: just initialize the control path and begin drawing
			@initializeControlPath(point)
			@beginDraw(false)
		else 									# in polygon mode:
			if not @controlPath?					# if the user just started the creation (first point, on mouse down)
				@initializeControlPath(point)		# 	initialize the control path, add the point and begin drawing
				@controlPath.add(point)
				@beginDraw(false)
			else 									# if the user already added some points: just add the point to the control path
				@controlPath.add(point)
			@controlPath.lastSegment.rtype = 'point'
		return

	# redefine {RPath#updateCreate}
	# update create action:
	# in normal mode:
	# - check if path is not in an RLock
	# - add point
	# - @checkUpdateDrawing() (i.e. continue the draw steps to fit the control path)
	# in polygon mode:
	# - update the [handleIn](http://paperjs.org/reference/segment/#handlein) and handleOut of the last segment
	# - draw in simplified (quick) mode
	# called on mouse drag
	# @param point [Point] the point to add
	# @param event [Event] the mouse event
	updateCreate: (point, event)->
		if not @data.polygonMode

			@controlPath.add(point)

			@checkUpdateDrawing(@controlPath.lastSegment, false)
		else
			# update the [handleIn](http://paperjs.org/reference/segment/#handlein) and handleOut of the last segment
			lastSegment = @controlPath.lastSegment
			previousSegment = lastSegment.previous
			previousSegment.rtype = 'smooth'
			previousSegment.handleOut = point.subtract(previousSegment.point)
			if lastSegment != @controlPath.firstSegment
				previousSegment.handleIn = previousSegment.handleOut.multiply(-1)
			lastSegment.handleIn = lastSegment.handleOut = null
			lastSegment.point = point
			console.log 'update create'
			@draw(true, false) 		# draw in simplified (quick) mode
		return

	# update create action: only used when in polygon mode
	# move the last point of the control path to the mouse position and draw in simple/quick mode
	# called on mouse move
	# @param event [Event] the mouse event
	createMove: (event)->
		@controlPath.lastSegment.point = event.point
		console.log 'create move'
		@draw(true, false)
		return

	# redefine {RPath#endCreate}
	# end create action:
	# - in polygon mode: just finish the path (@finiPath())
	# - in normal mode: compute speed, simplify path and update speed (necessary for SpeedPath) and finish path
	# @param point [Point] the point to add
	# @param event [Event] the mouse event
	endCreate: (point, event)->
		if @data.polygonMode then return 	# in polygon mode, finish is called by the path tool

		if @controlPath.segments.length>=2
			# if @speeds? then @computeSpeed()
			@controlPath.simplify()
			for segment in @controlPath.segments
				if segment.handleIn.length>200
					segment.handleIn = segment.handleIn.normalize().multiply(100)
					console.log 'ADJUSTING HANDLE LENGTH'
				if segment.handleOut.length>200
					segment.handleOut = segment.handleOut.normalize().multiply(100)
					console.log 'ADJUSTING HANDLE LENGTH'
			# if @speeds? then @updateSpeed()
		@finish()
		super()

		return

	# finish path creation:
	# @param loading [Boolean] (optional) whether the path is being loaded or being created by user
	finish: (loading=false)->
		if @data.polygonMode and not loading
			@controlPath.lastSegment.remove()
			@controlPath.lastSegment.handleOut = null

		if @controlPath.segments.length<2
			@remove()
			return

		if @data.smooth then @controlPath.smooth()

		if not loading
			@endDraw(loading)
			@drawingOffset = 0

		@rectangle = @controlPath.bounds

		if loading and @canvasRaster
			@draw(false, true) 	# enable to have the correct @canvasRaster size and to have the exact same result after a load or a change

		@initialize()
		return

	# in simplified mode, the path is drawn quickly, with less details
	# all parameters which are critical in terms of drawing time are set to *parameter.simplified*
	simplifiedModeOn: ()->
		@previousData = {}
		for folderName, folder of @constructor.parameters()
			for name, parameter of folder
				if parameter.simplified? and @data[name]?
					@previousData[name] = @data[name]
					@data[name] = parameter.simplified
		return

	# retrieve parameters values we had before drawing in simplified mode
	simplifiedModeOff: ()->
		for folderName, folder of @constructor.parameters()
			for name, parameter of folder
				if parameter.simplified? and @data[name]? and @previousData[name]?
					@data[name] = @previousData[name]
					delete @previousData[name]
		return

	# update the appearance of the path (the drawing group)
	# called anytime the path is modified:
	# by beginCreate/Update/End, updateSelect/End, parameterChanged, deletePoint, changePoint etc. and loadPath
	# - begin drawing (@beginDraw())
	# - update drawing (@updateDraw()) every *step* along the control path
	# - end drawing (@endDraw())
	# because the path are rendered on rasters, path are not drawn on load unless they are animated
	# @param simplified [Boolean] whether to draw in simplified mode or not (much faster)
	draw: (simplified=false, redrawing=true)->

		if @controlPath.segments.length < 2 then return

		if simplified then @simplifiedModeOn()

		# initialize dawing along control path
		# the control path is divided into n steps of fixed length, the last step will be smaller than others
		# to have a better result, the last (shorter) step is split in half and set as the first and the last step
		step = @data.step
		controlPathLength = @controlPath.length
		nf = controlPathLength/step
		nIteration  = Math.floor(nf)
		reminder = nf-nIteration
		offset = reminder*step/2

		@drawingOffset = 0

		process = ()=>
			@beginDraw(redrawing)

			# # update drawing (@updateDraw()) every *step* along the control path
			# # n=0
			# while offset<controlPathLength

			# 	@updateDraw(offset)
			# 	offset += step

			# 	# if n%10==0 then g.updateLoadingBar(offset/controlPathLength)
			# 	# n++

			for segment, i in @controlPath.segments
				if i==0 then continue
				@checkUpdateDrawing(segment, redrawing)

			@endDraw(redrawing)
			return

		if not g.catchErrors
			process()
		else
			try 	# catch errors to log them in the code editor console (if user is making a script)
				process()
			catch error
				console.error error.stack
				console.error error
				throw error

		if simplified
			@simplifiedModeOff()

		return

	# @return [Array of Paper point] a list of point from the control path converted in the planet coordinate system
	pathOnPlanet: ()->
		flatennedPath = @controlPath.copyTo(project)
		flatennedPath.flatten(@constructor.secureStep)
		flatennedPath.remove()
		return super(flatennedPath.segments)

	# get data, usually to save the RPath (some information must be added to data)
	# the control path is stored in @data.points and @data.planet
	getData: ()->
		@data.planet = g.projectToPlanet(@controlPath.segments[0].point)
		@data.points = []
		for segment in @controlPath.segments
			@data.points.push(g.projectToPosOnPlanet(segment.point))
			@data.points.push(g.pointToObj(segment.handleIn))
			@data.points.push(g.pointToObj(segment.handleOut))
			@data.points.push(segment.rtype)
		return @data

	# @see RPath.select
	# - bring control path to front and select it
	# - call RPath.select
	# @param updateOptions [Boolean] whether to update gui parameters with this RPath or not
	select: ()->
		if not super() then return
		@controlPath.selected = true
		if not @data.smooth then @controlPath.fullySelected = true
		return true

	# @see RPath.deselect
	# deselect control path, remove selection highlight (@see PrecisePath.highlightSelectedPoint) and call RPath.deselect
	deselect: ()->
		if not super() then return false
		# g.project.activeLayer.insertChild(@index, @controlPath)
		# control path can be null if user is removing the path
		@controlPath?.selected = false
		@selectionHighlight?.remove()
		@selectionHighlight = null
		return true

	# highlight selection path point:
	# draw a shape behind the selected point to be able to move and modify it
	# the shape is a circle if point is 'smooth', a square if point is a 'corner' and a triangle otherwise
	highlightSelectedPoint: ()->
		if not @controlPath.selected then return
		@selectionHighlight?.remove()
		@selectionHighlight = null
		if not @selectionState.segment? then return
		point = @selectionState.segment.point
		@selectionState.segment.rtype ?= 'smooth'
		switch @selectionState.segment.rtype
			when 'smooth'
				@selectionHighlight = new Path.Circle(point, 5)
			when 'corner'
				offset = new Point(5, 5)
				@selectionHighlight = new Path.Rectangle(point.subtract(offset), point.add(offset))
			when 'point'
				@selectionHighlight = new Path.RegularPolygon(point, 3, 5)
		@selectionHighlight.name = 'selection highlight'
		@selectionHighlight.controller = @
		@selectionHighlight.strokeColor = g.selectionBlue
		@selectionHighlight.strokeWidth = 1
		g.selectionLayer.addChild(@selectionHighlight)
		if @parameterControllers?.pointType? then g.setControllerValue(@parameterControllers.pointType, null, @selectionState.segment.rtype, @)
		return

	# redefine {RPath#initializeSelection}
	# Same functionnalities as {RPath#initializeSelection} (determine which action to perform depending on the the *hitResult*) but:
	# - adds handle selection initialization, and highlight selected points if any
	# - properly initialize transformation (rotation and scale) for PrecisePath
	initializeSelection: (event, hitResult) ->
		super(event, hitResult)

		specialKey = g.specialKey(event)

		if hitResult.type == 'segment'

			if specialKey and hitResult.item == @controlPath
				@selectionState = segment: hitResult.segment
				@deletePointCommand()
			else
				if hitResult.item == @controlPath
					@selectionState = segment: hitResult.segment

		if not @data.smooth
			if hitResult.type is "handle-in"
				@selectionState = segment: hitResult.segment, handle: hitResult.segment.handleIn
			else if hitResult.type is "handle-out"
				@selectionState = segment: hitResult.segment, handle: hitResult.segment.handleOut

		@highlightSelectedPoint()

		return

	# begin select action
	# @param event [Paper event] the mouse event
	beginSelect: (event) ->

		@selectionHighlight?.remove()
		@selectionHighlight = null

		super(event)

		if @selectionState.segment?
			@beginAction(new g.ModifyPointCommand(@))
		else if @selectionState.speedHandle?
			@beginAction(new g.ModifySpeedCommand(@))

		return

	updateSelect: (event)->
		# if not @drawing then g.updateView()
		super(event)
		return

	# add or update the selection rectangle (path used to rotate and scale the RPath)
	# @param reset [Boolean] (optional) true if must reset the selection rectangle (one of the control path segment has been modified)
	updateSelectionRectangle: (reset=false)->
		if reset
			# reset transform matrix to have @controlPath.rotation = 0 and @controlPath.scaling = 1,1
			@controlPath.firstSegment.point = @controlPath.firstSegment.point
			@rectangle = @controlPath.bounds.clone()
			@rotation = 0

		super()
		@controlPath.pivot = @selectionRectangle.pivot

		return

	setRectangle: (rectangle, update)->
		previousRectangle = @rectangle.clone()
		super(rectangle, update)
		@controlPath.pivot = previousRectangle.center
		@controlPath.rotate(-@rotation)
		@controlPath.scale(@rectangle.width/previousRectangle.width, @rectangle.height/previousRectangle.height)
		# @controlPath.position = @selectionRectangle.pivot
		# @controlPath.pivot = @selectionRectangle.pivot
		@controlPath.position = @rectangle.center
		@controlPath.pivot = @rectangle.center
		@controlPath.rotate(@rotation)
		return

	# setRotation: (rotation, update)->
	# 	previousRotation = @rotation
	# 	@drawing.pivot = @rectangle.center
	# 	super(rotation, update)
	# 	@controlPath.rotate(rotation-previousRotation)
	# 	@drawing.rotate(rotation-previousRotation)
	# 	return

	# smooth the point of *segment*, i.e. align the handles with the tangent at this point
	# @param segment [Paper Segment] the segment to smooth
	# @param offset [Number] (optional) the location of the segment (default is segment.location.offset)
	smoothPoint: (segment, offset)->
		segment.rtype = 'smooth'
		segment.linear = false

		offset ?= segment.location.offset
		tangent = segment.path.getTangentAt(offset)
		if segment.previous? then segment.handleIn = tangent.multiply(-0.25)
		if segment.next? then segment.handleOut = tangent.multiply(+0.25)

		# a second version of the smooth
		# if segment.previous? and segment.next?
		# 	delta = segment.next.point.subtract(segment.previous.point)
		# 	deltaN = delta.normalize()
		# 	previousToSegment = segment.point.subtract(segment.previous.point)
		# 	h = 0.5*deltaN.dot(previousToSegment)/delta.length
		# 	segment.handleIn = delta.multiply(-h)
		# 	segment.handleOut = delta.multiply(0.5-h)
		# else if segment.previous?
		# 	previousToSegment = segment.point.subtract(segment.previous.point)
		# 	segment.handleIn = previousToSegment.multiply(0.5)
		# else if segment.next?
		# 	nextToSegment = segment.point.subtract(segment.next.point)
		# 	segment.handleOut = nextToSegment.multiply(-0.5)
		return

	# double click event handler:
	# if we click on a point:
	# - roll over the three point modes (a 'smooth' point will become 'corner', a 'corner' will become 'point', and a 'point' will be deleted)
	# else if we clicked on the control path:
	# - create a point at *event* position
	# @param event [jQuery or Paper event] the mouse event
	doubleClick: (event)->
		# warning: event can be a jQuery event instead of a paper event

		# check if user clicked on the curve

		point = view.viewToProject(new Point(event.pageX, event.pageY))

		hitResult = @performHitTest(point, @constructor.hitOptions)

		if not hitResult? 	# return if user did not click on the curve
			return

		switch hitResult.type
			when 'segment' 										# if we click on a point: roll over the three point modes

				segment = hitResult.segment
				@selectionState.segment = segment

				switch segment.rtype
					when 'smooth', null, undefined
						@modifySelectedPointType('corner')
					when 'corner'
						@modifySelectedPointType('point')
					when 'point'
						@deletePointCommand()
					else
						console.log "segment.rtype not known."

			when 'stroke', 'curve' 								# else if we clicked on the control path: create a point at *event* position
				@addPointCommand(hitResult.location)

		return

	addPointCommand: (location)->
		g.commandManager.add(new g.AddPointCommand(@, location), true)
		return

	addPointAt: (location, update=true)->
		if not CurveLocation.prototype.isPrototypeOf(location) then location = @controlPath.getLocationAt(location)
		return @addPoint(location.index, location.point, location.offset, update)

	# add a point according to *hitResult*
	# @param location [Paper Location] the location where to add the point
	# @param update [Boolean] whether update is required
	# @return the new Segment
	addPoint: (index, point, offset, update=true)->

		segment = @controlPath.insert(index + 1, new Point(point))

		if @data.smooth
			@controlPath.smooth()
		else
			@smoothPoint(segment, offset)

		@draw()
		if not @socketAction
			segment.selected = true
			@selectionState.segment = segment
			@highlightSelectedPoint()
			if update then @update('point')
			g.chatSocket.emit "bounce", itemPk: @pk, function: "addPoint", arguments: [index, point, offset, false]
		return segment

	deletePointCommand: ()->
		if not @selectionState.segment? then return
		g.commandManager.add(new g.DeletePointCommand(@, @selectionState.segment), true)
		return

	# delete the point of *segment* (from curve) and delete curve if there are no points anymore
	# @param segment [Paper Segment or segment index] the segment to delete
	# @return the location of the deleted point (to be able to re-add it in case of a undo)
	deletePoint: (segment, update=true)->
		if not segment then return
		if not Segment.prototype.isPrototypeOf(segment) then segment = @controlPath.segments[segment]
		@selectionState.segment = if segment.next? then segment.next else segment.previous
		if @selectionState.segment then @selectionHighlight.position = @selectionState.segment.point
		location = { index: segment.location.index - 1, point: segment.location.point }
		segment.remove()
		if @controlPath.segments.length <= 1
			@deleteCommand()
			return
		if @data.smooth then @controlPath.smooth()
		@draw()
		if not @socketAction
			@updateSelectionRectangle(true)
			if update then @update('point')
			g.chatSocket.emit "bounce", itemPk: @pk, function: "deletePoint", arguments: [segment.index, false]
		return location

	# delete the selected point (from curve) and delete curve if there are no points anymore
	# emit the action to websocket
	deleteSelectedPoint: ()->
		@deletePoint(@selectionState.segment)
		return

	modifyPointTypeCommand: (rtype)->
		g.commandManager.add(new g.ModifyPointTypeCommand(@, @selectionState.segment, rtype), true)
		return

	# change selected segment position and handle position
	# @param position [Paper Point] the new position
	# @param handleIn [Paper Point] the new handle in position
	# @param handleOut [Paper Point] the new handle out position
	# @param update [Boolean] whether we must update the path (for example when it is a command) or not
	# @param draw [Boolean] whether we must draw the path or not
	modifySelectedPoint: (position, handleIn, handleOut, fastDraw=true, update=true)->
		@modifyPoint(@selectionState.segment, position, handleIn, handleOut, fastDraw, update)
		return

	modifyPoint: (segment, position, handleIn, handleOut, fastDraw=true, update=true)->
		if not Segment.prototype.isPrototypeOf(segment) then segment = @controlPath.segments[segment]
		segment.point = new Point(position)
		segment.handleIn = new Point(handleIn)
		segment.handleOut = new Point(handleOut)
		@draw(fastDraw)
		if fastDraw and @selectionHighlight?
			@selectionHighlight.position = segment.point
			@selectionHighlight.bringToFront()
		else
			@highlightSelectedPoint()
		if @selectionRectangle? then @updateSelectionRectangle(true)
		if not @socketAction
			if update then @update('segment')
			g.chatSocket.emit "bounce", itemPk: @pk, function: "modifyPoint", arguments: [segment.index, position, handleIn, handleOut, fastDraw, false]
		return

	updateModifyPoint: (event)->
		# segment.rtype == null or 'smooth': handles are aligned, and have the same length if shit
		# segment.rtype == 'corner': handles are not equal
		# segment.rtype == 'point': no handles
		segment = @selectionState.segment

		if @selectionState.handle? 									# move the selected handle

			if g.getSnap() >= 1
				point = g.snap2D(event.point)
				@selectionState.handle.x = point.x - segment.point.x
				@selectionState.handle.y = point.y - segment.point.y
			else
				@selectionState.handle.x += event.delta.x
				@selectionState.handle.y += event.delta.y

			if segment.rtype == 'smooth' or not segment.rtype?
				if @selectionState.handle == segment.handleOut and not segment.handleIn.isZero()
					if not event.modifiers.shift
						segment.handleIn = segment.handleOut.normalize().multiply(-segment.handleIn.length)
					else
						segment.handleIn = segment.handleOut.multiply(-1)
				if @selectionState.handle == segment.handleIn and not segment.handleOut.isZero()
					if not event.modifiers.shift
						segment.handleOut = segment.handleIn.normalize().multiply(-segment.handleOut.length)
					else
						segment.handleOut = segment.handleIn.multiply(-1)

		else if @selectionState.segment?								# move the selected point

			if g.getSnap() >= 1
				point = g.snap2D(event.point)
				segment.point.x = point.x
				segment.point.y = point.y
			else
				segment.point.x += event.delta.x
				segment.point.y += event.delta.y

		g.validatePosition(@, null, true)
		@modifyPoint(segment, segment.point, segment.handleIn, segment.handleOut, true, false)

		return

	endModifyPoint: ()->
		if @data.smooth then @controlPath.smooth()
		@draw()
		@selectionHighlight.bringToFront()
		@update('points')
		return

	modifySelectedPointType: (value, update=true)->
		if not @selectionState.segment? then return
		@modifyPointType(@selectionState.segment, value, update)
		return

	# - set selected point mode to *rtype*: 'smooth', 'corner' or 'point'
	# - update the selected point highlight
	# - emit action to websocket
	# @param rtype [String] new mode of the point: can be 'smooth', 'corner' or 'point'
	# @param update [Boolean] whether update is required
	modifyPointType: (segment, rtype, update=true)->
		if not Segment.prototype.isPrototypeOf(segment) then segment = @controlPath.segments[segment]
		if @data.smooth then return
		@selectionState.segment.rtype = rtype
		switch rtype
			when 'corner'
				if @selectionState.segment.linear = true
					@selectionState.segment.linear = false
					@selectionState.segment.handleIn = @selectionState.segment.previous.point.subtract(@selectionState.segment.point).multiply(0.5)
					@selectionState.segment.handleOut = @selectionState.segment.next.point.subtract(@selectionState.segment.point).multiply(0.5)
			when 'point'
				@selectionState.segment.linear = true
			when 'smooth'
				@smoothPoint(@selectionState.segment)
		@draw()
		@highlightSelectedPoint()
		if not @socketAction
			if update then @update('point')
			g.chatSocket.emit "bounce", itemPk: @pk, function: "modifyPointType", arguments: [segment.index, rtype, false]
		return

	# overload {RPath#parameterChanged}, but update the control path state if 'smooth' was changed
	# called when a parameter is changed
	setParameter: (name, value, updateGUI, update)->
		super(name, value, updateGUI, update)
		if name == 'smooth'
			# todo: add a warning when changing smooth?
			if @data.smooth 		# todo: put this in @draw()? and remove this function?
				@controlPath.smooth()
				@controlPath.fullySelected = false
				@controlPath.selected = true
				segment.rtype = 'smooth' for segment in @controlPath.segments
			else
				@controlPath.fullySelected = true
		return

	# overload {RPath#remove}, but in addition: remove the selected point highlight and the canvas raster
	remove: ()->
		@selectionHighlight = null
		@canvasRaster = null
		super()
		return

tool = new g.PathTool(PrecisePath, true)