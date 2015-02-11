log  = require 'a-mo.Log'
Math = require 'a-mo.Math'
bit  = require 'bit'

class Transform
	@version: 0x010200
	@version_major: bit.rshift( @version, 16 )
	@version_minor: bit.band( bit.rshift( @version, 8 ), 0xFF )
	@version_patch: bit.band( @version, 0xFF )
	@version_string: ("%d.%d.%d")\format @version_major, @version_minor, @version_patch

	tags = tags or require 'a-mo.Tags'

	-- An alternate constructor.
	@fromString: ( transformString, lineDuration, tagIndex, parentLine ) =>
		transStart, transEnd, transExp, transEffect = transformString\match "%(([%-%d]*),?([%-%d]*),?([%d%.]*),?(.+)%)"
		-- Catch the case of \t(2.345,\1c&H0000FF&), where the 2 gets
		-- matched to transStart and the .345 gets matched to transEnd.
		if tonumber( transStart ) and not tonumber( transEnd )
			transExp = transStart .. transExp
			transStart = ""

		transExp = tonumber( transExp ) or 1
		transStart = tonumber( transStart ) or 0

		transEnd = tonumber( transEnd ) or 0
		if transEnd == 0
			transEnd = lineDuration

		object = @ transStart, transEnd, transExp, transEffect, tagIndex, parentLine
		object.rawString = transformString
		return object

	new: ( @startTime, @endTime, @accel, @effect, @index, @parentLine ) =>
		@gatherTagsInEffect!

	__tostring: => return @toString!
	toString: ( line = @parentLine ) =>
		if @effect == ""
			return ""
		elseif @endTime <= 0
			line.transformEnded = true
			return @effect
		elseif @startTime > line.duration or @endTime < @startTime
			return ""
		elseif @accel == 1
			return ("\\t(%s,%s,%s)")\format @startTime, @endTime, @effect
		else
			return ("\\t(%s,%s,%s,%s)")\format @startTime, @endTime, @accel, @effect

	gatherTagsInEffect: =>
		if @effectTags
			return
		@effectTags = { }
		for tag in *tags.transformTags
			@effect\gsub tag.pattern, ( value ) ->
				log.debug "Found tag: %s -> %s", tag.name, value
				unless @effectTags[tag]
					@effectTags[tag] = { }
				endValue = tag\convert value
				table.insert @effectTags[tag], endValue
				@effectTags[tag].last = endValue

	collectPriorState: ( line, text, placeholder ) =>
		@priorValues = { k, v for k, v in pairs line.properties }
		-- Fill out all of the possible tag defaults for tags that aren't
		-- defined by styles. This works great for everything except \clip,
		-- which defaults to 0, 0, width, height
		for tag in *tags.transformTags
			unless tag.style
				@priorValues[tag] = 0

		@priorValues[tags.allTags.rectClip]  = { 0, 0, line.parentCollection.meta.PlayResX, line.parentCollection.meta.PlayResY }
		@priorValues[tags.allTags.rectiClip] = { 0, 0, line.parentCollection.meta.PlayResX, line.parentCollection.meta.PlayResY }

		count = math.floor @index
		i = 1
		text\gsub "({.-})", ( tagBlock ) ->
			if i == count
				tagBlock = tagBlock\gsub "(.+)#{placeholder}", "%1"

			for tag, _ in pairs @effectTags
				if tag.affectedBy
					newTagBlock = tagBlock\gsub ".-"..tag.pattern, ( value ) ->
						@priorValues[tag] = tag\convert value
						return ""
					for tagName in *tag.affectedBy
						newTag = tags.allTags[tagName]
						newTagBlock = newTagBlock\gsub ".-"..newTag.pattern, ( value ) ->
							@priorValues[tag] = newTag\convert value
							return ""
				else
					tagBlock\gsub tag.pattern, ( value ) ->
						@priorValues[tag] = tag\convert value

			i += 1
			return nil,
			count

	interpolate: ( line, text, index, time ) =>
		log.dump time
		placeholder = line.tPlaceholder index
		@collectPriorState line, text, placeholder

		linearProgress = (time - @startTime)/(@endTime - @startTime)
		progress = math.pow linearProgress, @accel

		text = text\gsub placeholder, ->
			resultString = {}
			for tag, endValues in pairs @effectTags
				if linearProgress <= 0
					return tag\format @priorValues[tag]
				elseif linearProgress >= 1
					return tag\format endValues.last

				value = @priorValues[tag]
				for endValue in *endValues
					value = tag\interpolate value, endValue, progress

				table.insert resultString, tag\format value

			return table.concat resultString

		return text
