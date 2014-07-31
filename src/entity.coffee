angular.module("konzilo.entity", [])
.provider("kzEntityInfo", ->
  @entities = {}
  addProvider: (name, info) =>
    defaultValidators =
      Number: _.isNumber
      Boolean: _.isBoolean
      String: _.isString
      Object: _.isObject
      Array: _.isArray

    for property in info.properties
      if not property.validator and property.type and
      defaultValidators[property.type]
        property.validator = defaultValidators[property.type]
    @entities[name] = info
  $get: =>
    (name) => @entities[name]
)
.factory("kzLoadTemplate",
["$templateCache", "$q", "$http", ($templateCache, $q, $http) ->
  (options) ->
    if options.template
      $q.when(options.template)
    else if options.templateUrl
      $http.get(options.templateUrl, { cache: $templateCache })
      .then (response) -> return response.data
])
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
.factory("kzEntity",
["kzEntityInfo", "kzEntityManager", "$controller", "$compile", "kzLoadTemplate", '$q',
(entityInfo, storage, $controller, $compile, loadTemplate, $q)->
  class Entity
    constructor: (@name, @data) ->
      @info = entityInfo(@name)
      @storage = storage(@name)
      @data = data

      for prop, info of @info.properties when info.processor and (info.processEmpty or @data[prop])
        if not _.isFunction(info.processor)
          processor = $injector.get(info.processor)
        else
          processor = info.processor
        @data[prop] = processor(@data[prop], @) if processor
      @dirty = false

    save: (callback, errorCallback) ->
      @storage.save @, callback, errorCallback

    remove: (callback, errorCallback) ->
      @storage.remove @, callback, errorCallback

    toObject: -> @data

    setData: (@data) ->

    get: (name) -> @data[name]

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
      promises = []
      results = {}
      formatStatus = (validator, validatorResult) ->
        status =
          result: validatorResult
        status.message = validator.errorMessage if not result
        status.message = validator.successMessage if result
        return status

      checkEmpty = (value) ->
        if typeof value == 'string' or value?.isArray?()
          return value.length == 0
        else
          return not value

      formatEntityStatus = (status) ->
        valid: _.every(status, result: true)
        properties: status

      for prop, settings of @info.properties when settings.validator or settings.required
        value = @get(prop)
        empty = checkEmpty(value)
        if empty and settings.required
          results[prop] = formatStatus(errorMessage: "#{prop} is required",
            false)
        continue if empty
        result = settings.validator.check(value, @)
        if result?.then
          result.property = prop
          promises.push(result)

        else
          results[prop] = formatStatus(settings.validator, result)

      if promises.length > 0
        deferred = $q.defer()
        resolvePromises = (promises) ->
          if promises.length == 0
            deferred.resolve(formatEntityStatus(results))
          promise = promises.shift()
          promise.then (result) ->
            results[promise.prop] = formatStatus(result,
              @info.properties[promise.prop].validator)
            resolvePromises(promises)
          , deferred.reject
        resolvePromises(promises)
        return deferred.promise
      return $q.when(formatEntityStatus(results))

    view: (options) ->
      if options.mode
        mode = @info.viewModes[options.mode]
      else if @info.defaultViewMode
        mode = @info.viewModes[@info.defaultViewMode]
      else
        mode = _.first(_.toArray(@info.viewModes))
      if mode
        loadTemplate(mode).then (template) ->
          options.element.html(template)
          if mode.controller
            $controller mode.controller,
            { $scope: options.scope, entity: options.entity }
          $compile(options.element.contents())(options.scope)
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

    query: (q) ->
      if q?.reset
        @cache.removeAll()
        delete q.reset
      for key, item of q
        q[key] = JSON.stringify(item) if _.isPlainObject(item)
      $http.get(@url, { params: q, cache: @cache }).then (result) =>
        data = result.data
        new Collection(@name, data, q, @entityClass)

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
.directive("entityView",
["$controller", "$compile", "kzEntityManager", "$q",
($controller, $compile, entityManager, $q) ->
  restrict: 'AE'
  scope: { "entity": "=" }
  link: (scope, element, attrs) ->
    entity = scope.entity
    type = entity?.type or attrs.entityType
    id = entity?.id() or attrs.entityId
    mode = attrs.mode
    if entity
      entityPromise = $q.when(entity)
    else
      deferred = $q.defer()
      entityManager(type).get id, (result) ->
        deferred.resolve result
      entityPromise = deferred.promise

    entityPromise.then (result) ->
      result.view
        scope: scope
        type: type
        element: element
        attrs: attrs
        entity: result
        mode: attrs.mode
])
