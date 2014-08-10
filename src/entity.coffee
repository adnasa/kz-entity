angular.module("konzilo.entity", [])
.provider("kzEntityInfo", ->
  @entities = {}
  addProvider: (name, info) =>
    @entities[name] = info
  $get: =>
    (name) => @entities[name]
)
.factory("kzEntityManager",
["kzEntityInfo", "$injector", (entityInfo, $injector) ->
  controllers = {}
  (name) ->
    controllerName = entityInfo(name)?.storageController
    return undefined if not controllerName
    if not controllers[name]
      controllerClass = new $injector.get(controllerName)
      controllers[name] = new controllerClass(name)
    return controllers[name]
])
.service('kzEntityValidator', ['kzEntityInfo', '$q', '$injector',
(entityInfo, $q, $injector) ->
  formatEntityStatus = (status) ->
    propertyStatus = {}
    for prop in status
      propertyStatus[prop.name] = prop
    valid: _.every(status, valid: true)
    properties: propertyStatus

  formatPropertyStatus = (name, status) ->
    valid: _.every(status, result: true)
    name: name
    results: status

  formatValidatorStatus = (validator, result) ->
    status =
      result: result
      message: validator.errorMessage
    return status

  checkEmpty = (value) ->
    if typeof value == 'string' or value?.isArray?()
      return value.length == 0
    else
      return not value

  class EntityValidator
    constructor: (@type, @entity) ->
      @info = entityInfo(@type)
    # Validate the entity. Returns a promise
    # which resolves as an object containing the following:
    # **valid**: true or false
    # **properties**: an object with the result for each property.
    validate: () ->
      promises = (@validateProperty(name) for name in _.keys(@info.properties))
      $q.all(promises).then (results) ->
        formatted = formatEntityStatus(results)
        return formatted

    # Validate a specific property on the the entity.
    # **name**: the name of the entity.
    # @return a promise with the result of the validators that have been run.
    validateProperty: (name) ->
      results = []
      promises = []
      value = @entity.get(name)
      settings = @info.properties[name]
      empty = checkEmpty(value)
      # Empty is a special case. This is because
      # we might not want to continue if the property
      # is empty.
      if empty and settings.required
        return $q.when(formatPropertyStatus(name, [formatValidatorStatus(
          errorMessage: "#{name} is required", false)]))

      # This is not required, and the value is empty,
      # so it's pointless to run more validators after this point.
      if empty or not settings.validators
        return $q.when(formatPropertyStatus(name, []))

      for validator in settings.validators
        # Try to inject to validator if it is defined as a string.
        if _.isString(validator)
          validator = $injector.get(validator)
        else
          validator = validator

        result = validator.check(value, @entity)
        # Validators can either return a promise
        # or a result directly.
        if result?.then
          result.validator = validator
          promises.push(result)
        else
          results.push(formatValidatorStatus(validator, result))

      if promises.length > 0
        return $q.all(promises).then (promisedResults) ->
          formattedResults = for result, index in promisedResults
            formatValidatorStatus(promises[index].validator, result)
          return formatPropertyStatus(name, _.union(formattedResults, results))
      else
        return $q.when(formatPropertyStatus(name, results))
])
.factory("kzEntity",
["kzEntityInfo", "kzEntityManager", "$controller", "$compile",
'$q', "$injector",
(entityInfo, storage, $controller, $compile, $q, $injector) ->
  class Entity
    constructor: (@name, @data) ->
      @info = entityInfo(@name)
      @storage = storage(@name)
      @data = data
      @dirty = false

    save: (callback, errorCallback) ->
      @storage.save @, callback, errorCallback

    remove: (callback, errorCallback) ->
      @storage.remove @, callback, errorCallback

    toObject: -> @data

    setData: (@data) ->

    get: (name) ->
      val = @data[name]
      return val if not @info.properties[name]?.processor
      processor = @info.properties[name].processor
      if not _.isFunction(processor)
        processor = $injector.get(processor)
      else
        processor = processor
      return processor(val, @) if processor

    uri: -> @data.links?.self?.href

    set: (name, data) ->
      if _.isPlainObject(_.clone(name))
        @data[prop] = value for prop, value of name
      else
        @data[name] = data
      @dirty = true
      return @

    id: -> @data[@info.idProperty]

    idProperty: -> @info.idProperty

    label: -> @data[@info.labelProperty]

    labelProperty: -> @info.labelProperty

    isNew: -> !@data[@info.idProperty]

    validate: ->
      validator = new ($injector.get(@info.validator))(@name, @)
      validator.validate()
])

.factory("kzCollection",
["kzEntityInfo", "kzEntityManager", "kzEntity",
(entityInfo, entityManager, Entity) ->
  class Collection
    constructor: (@name, result, @query=null, @entityClass=Entity) ->
      @count = 0
      @limit = 0
      @storage = entityManager(@name)
      name = @name.toLowerCase()
      # This is in HAL format and contains many embedded entities.
      if _.isPlainObject(result) and result._embedded[name]
        data = result._embedded[name]
        @count = result.count
        @skip = result.skip
        @limit = result.limit
      else
        data = result
        @count = data.length
      # Make sure all items are wrapped in entity classes.
      @data = for item in data
        if not item.toObject
          new @entityClass(@name, item)
        else
          item

    toArray: -> item.toObject() for item in @data

    get: (item) ->
      if not _.isPlainObject(item) and not item.toObject
        return _.find @data, (value) -> value.id() is item

      if not item.toObject
        item = new @entityClass(@name, @data)

      _.find @data, (value) ->
        value.id() is item.id()

    hasItem: (item) ->
      if @get(item) then true else false

    find: (query) ->
      _.find @data, (item) ->
        if _.isPlainObject(query)
          for key, value of query
            return false if item.get(key) != value
          return true
        if _.isFunction(query)
          return query(item)

    getPage: (page) ->
      query = _.clone(@query)
      query.skip = @limit * page
      @storage.query(query)

    page: -> @skip/@limit

    pages: ->
      return 0 if @limit > @count
      return (@count - (@count%@limit))/@limit

])

# Save things the REST way using angular $http.
.factory("kzHttpStorage",
["kzEntity", "kzCollection",
"kzEntityInfo", "$q", "$http", "$cacheFactory",
(Entity, Collection,
entityInfo, $q, $http, $cacheFactory) ->
  class Storage
    constructor: (@name) ->
      @info = entityInfo(@name)
      @url = @info.url
      params = {}
      params[@info.idProperty] = "@#{@info.idProperty}"
      actions =
        update:
          method: "PUT"
          params: params

      @cache = $cacheFactory("#{@url}:#{name}")
      @eventCallbacks = {}

    save: (item) ->
      @cache.removeAll()
      if not item.toObject
        item = new Entity(@name, item)

      @triggerEvent("preSave", item).then (item) =>
        data = item.toObject()
        if item.isNew()
          request = $http.post(@url, data)
        else
          request = $http.put("#{@url}/#{item.id()}", data)
        request.then (result) =>
          item.setData(result.data)
          @triggerEvent("itemSaved", item)
          @triggerEvent("changed", item)
          return item

    remove: (item) ->
      @cache.removeAll()
      if _.isPlainObject(item)
        url = "#{@url}/#{item[@info.idProperty]}"
      else if _.isFunction(item.id)
        url = "#{@url}/#{item.id()}"
      else
        url = "#{@url}/#{item}"
      $http.delete(url).then (result) =>
        @triggerEvent("itemRemoved", item) if result
        @triggerEvent("changed", item)
        return new Entity(@name, result.data)

    get: (item) ->
      if _.isPlainObject(item)
        item = item[@info.idProperty]
      $http.get("#{@url}/#{item}", cache: @cache).then (result) =>
        new Entity(@name, result.data)

    sorted: (order, callback, errorCallback) ->
      @storage.query { _orderby: order }, (result) =>
        callback(new Collection(@name, result, 0, 0, @entityClass))
      , errorCallback

    query: (q, options = {}) ->
      options = _.defaults options,
        reset: false
        wrapped: true
      if options.reset
        @cache.removeAll()
      for key, item of q
        q[key] = JSON.stringify(item) if _.isPlainObject(item)
      $http.get(@url, { params: q, cache: @cache }).then (result) =>
        data = result.data
        collection = new Collection(@name, data, q, @entityClass)
        if options.wrapped then collection else collection.toArray()

    clearCache: -> @cache.removeAll()

    # Trigger a particular event.
    triggerEvent: (event, item) ->
      promises = []
      if @eventCallbacks[event]
        for callback in @eventCallbacks[event]
          result = callback(item)
          promises.push(result) if result?.then

      deferred = $q.defer()
      resolveCallback = (result)->
        if promises.length == 0
          deferred.resolve(result)
        else
          promises.shift().then(resolveCallback)

      if promises.length == 0
        return $q.when(item)
      promises.shift().then(resolveCallback)
      return deferred.promise

    # Item removed event.
    itemRemoved: (fn) ->
      @on "itemRemoved", fn

    # Item saved event.
    itemSaved: (fn) ->
      @on "itemSaved", fn

    preSave: (fn) ->
      @on "preSave", fn

    changed: (fn) ->
      @on "changed", fn

    on: (event, fn) ->
      if not @eventCallbacks[event]
        @eventCallbacks[event] = []
      @eventCallbacks[event].push fn
])
