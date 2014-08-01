(function() {
  angular.module("konzilo.entity", []).provider("kzEntityInfo", function() {
    this.entities = {};
    return {
      addProvider: (function(_this) {
        return function(name, info) {
          return _this.entities[name] = info;
        };
      })(this),
      $get: (function(_this) {
        return function() {
          return function(name) {
            return _this.entities[name];
          };
        };
      })(this)
    };
  }).factory("kzEntityManager", [
    "kzEntityInfo", "$injector", function(entityInfo, $injector) {
      var controllers;
      controllers = {};
      return function(name) {
        var controllerClass, controllerName, _ref;
        controllerName = (_ref = entityInfo(name)) != null ? _ref.storageController : void 0;
        if (!controllerName) {
          return void 0;
        }
        if (!controllers[name]) {
          controllerClass = new $injector.get(controllerName);
          controllers[name] = new controllerClass(name);
        }
        return controllers[name];
      };
    }
  ]).service('kzEntityValidator', [
    'kzEntityInfo', '$q', '$injector', function(entityInfo, $q, $injector) {
      var EntityValidator, checkEmpty, formatEntityStatus, formatPropertyStatus, formatValidatorStatus;
      formatEntityStatus = function(status) {
        var prop, propertyStatus, _i, _len;
        propertyStatus = {};
        for (_i = 0, _len = status.length; _i < _len; _i++) {
          prop = status[_i];
          propertyStatus[prop.name] = prop;
        }
        return {
          valid: _.every(status, {
            valid: true
          }),
          properties: propertyStatus
        };
      };
      formatPropertyStatus = function(name, status) {
        return {
          valid: _.every(status, {
            result: true
          }),
          name: name,
          results: status
        };
      };
      formatValidatorStatus = function(validator, result) {
        var status;
        status = {
          result: result,
          message: validator.errorMessage
        };
        return status;
      };
      checkEmpty = function(value) {
        if (typeof value === 'string' || (value != null ? typeof value.isArray === "function" ? value.isArray() : void 0 : void 0)) {
          return value.length === 0;
        } else {
          return !value;
        }
      };
      return EntityValidator = (function() {
        function EntityValidator(type, entity) {
          this.type = type;
          this.entity = entity;
          this.info = entityInfo(this.type);
        }

        EntityValidator.prototype.validate = function() {
          var name, promises;
          promises = (function() {
            var _i, _len, _ref, _results;
            _ref = _.keys(this.info.properties);
            _results = [];
            for (_i = 0, _len = _ref.length; _i < _len; _i++) {
              name = _ref[_i];
              _results.push(this.validateProperty(name));
            }
            return _results;
          }).call(this);
          return $q.all(promises).then(function(results) {
            var formatted;
            formatted = formatEntityStatus(results);
            return formatted;
          });
        };

        EntityValidator.prototype.validateProperty = function(name) {
          var empty, promises, result, results, settings, validator, value, _i, _len, _ref;
          results = [];
          promises = [];
          value = this.entity.get(name);
          settings = this.info.properties[name];
          empty = checkEmpty(value);
          if (empty && settings.required) {
            return $q.when(formatPropertyStatus(name, [
              formatValidatorStatus({
                errorMessage: "" + name + " is required"
              }, false)
            ]));
          }
          if (empty || !settings.validators) {
            return $q.when(formatPropertyStatus(name, []));
          }
          _ref = settings.validators;
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            validator = _ref[_i];
            if (_.isString(validator)) {
              validator = $injector.get(validator);
            } else {
              validator = validator;
            }
            result = validator.check(value, this.entity);
            if (result != null ? result.then : void 0) {
              result.validator = validator;
              promises.push(result);
            } else {
              results.push(formatValidatorStatus(validator, result));
            }
          }
          if (promises.length > 0) {
            return $q.all(promises).then(function(promisedResults) {
              var formattedResults, index;
              formattedResults = (function() {
                var _j, _len1, _results;
                _results = [];
                for (index = _j = 0, _len1 = promisedResults.length; _j < _len1; index = ++_j) {
                  result = promisedResults[index];
                  _results.push(formatValidatorStatus(promises[index].validator, result));
                }
                return _results;
              })();
              return formatPropertyStatus(name, _.union(formattedResults, results));
            });
          } else {
            return $q.when(formatPropertyStatus(name, results));
          }
        };

        return EntityValidator;

      })();
    }
  ]).factory("kzEntity", [
    "kzEntityInfo", "kzEntityManager", "$controller", "$compile", '$q', "$injector", function(entityInfo, storage, $controller, $compile, $q, $injector) {
      var Entity;
      return Entity = (function() {
        function Entity(name, data) {
          this.name = name;
          this.data = data;
          this.info = entityInfo(this.name);
          this.storage = storage(this.name);
          this.data = data;
          this.dirty = false;
        }

        Entity.prototype.save = function(callback, errorCallback) {
          return this.storage.save(this, callback, errorCallback);
        };

        Entity.prototype.remove = function(callback, errorCallback) {
          return this.storage.remove(this, callback, errorCallback);
        };

        Entity.prototype.toObject = function() {
          return this.data;
        };

        Entity.prototype.setData = function(data) {
          this.data = data;
        };

        Entity.prototype.get = function(name) {
          var processor, val, _ref;
          val = this.data[name];
          if (!((_ref = this.info.properties[name]) != null ? _ref.processor : void 0)) {
            return val;
          }
          processor = this.info.properties[name].processor;
          if (!_.isFunction(processor)) {
            processor = $injector.get(processor);
          } else {
            processor = processor;
          }
          if (processor) {
            return processor(val, this);
          }
        };

        Entity.prototype.uri = function() {
          var _ref, _ref1;
          return (_ref = this.data.links) != null ? (_ref1 = _ref.self) != null ? _ref1.href : void 0 : void 0;
        };

        Entity.prototype.set = function(name, data) {
          var prop, value;
          if (_.isPlainObject(_.clone(name))) {
            for (prop in name) {
              value = name[prop];
              this.data[prop] = value;
            }
          } else {
            this.data[name] = data;
          }
          this.dirty = true;
          return this;
        };

        Entity.prototype.id = function() {
          return this.data[this.info.idProperty];
        };

        Entity.prototype.idProperty = function() {
          return this.info.idProperty;
        };

        Entity.prototype.label = function() {
          return this.data[this.info.labelProperty];
        };

        Entity.prototype.labelProperty = function() {
          return this.info.labelProperty;
        };

        Entity.prototype.isNew = function() {
          return !this.data[this.info.idProperty];
        };

        Entity.prototype.validate = function() {
          var validator;
          validator = new ($injector.get(this.info.validator))(this.name, this);
          return validator.validate();
        };

        return Entity;

      })();
    }
  ]).factory("kzCollection", [
    "kzEntityInfo", "kzEntityManager", "kzEntity", function(entityInfo, entityManager, Entity) {
      var Collection;
      return Collection = (function() {
        function Collection(name, result, query, entityClass) {
          var data, item;
          this.name = name;
          this.query = query != null ? query : null;
          this.entityClass = entityClass != null ? entityClass : Entity;
          this.count = 0;
          this.limit = 0;
          this.storage = entityManager(this.name);
          name = this.name.toLowerCase();
          if (_.isPlainObject(result) && result._embedded[name]) {
            data = result._embedded[name];
            this.count = result.count;
            this.skip = result.skip;
            this.limit = result.limit;
          } else {
            data = result;
            this.count = data.length;
          }
          this.data = (function() {
            var _i, _len, _results;
            _results = [];
            for (_i = 0, _len = data.length; _i < _len; _i++) {
              item = data[_i];
              if (!item.toObject) {
                _results.push(new this.entityClass(this.name, item));
              } else {
                _results.push(item);
              }
            }
            return _results;
          }).call(this);
        }

        Collection.prototype.toArray = function() {
          var item, _i, _len, _ref, _results;
          _ref = this.data;
          _results = [];
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            item = _ref[_i];
            _results.push(item.toObject());
          }
          return _results;
        };

        Collection.prototype.get = function(item) {
          if (!_.isPlainObject(item) && !item.toObject) {
            return _.find(this.data, function(value) {
              return value.id() === item;
            });
          }
          if (!item.toObject) {
            item = new this.entityClass(this.name, this.data);
          }
          return _.find(this.data, function(value) {
            return value.id() === item.id();
          });
        };

        Collection.prototype.hasItem = function(item) {
          if (this.get(item)) {
            return true;
          } else {
            return false;
          }
        };

        Collection.prototype.find = function(query) {
          return _.find(this.data, function(item) {
            var key, value;
            if (_.isPlainObject(query)) {
              for (key in query) {
                value = query[key];
                if (item.get(key) !== value) {
                  return false;
                }
              }
              return true;
            }
            if (_.isFunction(query)) {
              return query(item);
            }
          });
        };

        Collection.prototype.getPage = function(page) {
          var query;
          query = _.clone(this.query);
          query.skip = this.limit * page;
          return this.storage.query(query);
        };

        Collection.prototype.page = function() {
          return this.skip / this.limit;
        };

        Collection.prototype.pages = function() {
          if (this.limit > this.count) {
            return 0;
          }
          return (this.count - (this.count % this.limit)) / this.limit;
        };

        return Collection;

      })();
    }
  ]).factory("kzHttpStorage", [
    "kzEntity", "kzCollection", "kzEntityInfo", "$q", "$http", "$cacheFactory", function(Entity, Collection, entityInfo, $q, $http, $cacheFactory) {
      var Storage;
      return Storage = (function() {
        function Storage(name) {
          var actions, params;
          this.name = name;
          this.info = entityInfo(this.name);
          this.url = this.info.url;
          params = {};
          params[this.info.idProperty] = "@" + this.info.idProperty;
          actions = {
            update: {
              method: "PUT",
              params: params
            }
          };
          this.cache = $cacheFactory("" + this.url + ":" + name);
          this.eventCallbacks = {};
        }

        Storage.prototype.save = function(item) {
          this.cache.removeAll();
          if (!item.toObject) {
            item = new Entity(this.name, item);
          }
          return this.triggerEvent("preSave", item).then((function(_this) {
            return function(item) {
              var data, request;
              data = item.toObject();
              if (item.isNew()) {
                request = $http.post(_this.url, data);
              } else {
                request = $http.put("" + _this.url + "/" + (item.id()), data);
              }
              return request.then(function(result) {
                item.setData(result.data);
                _this.triggerEvent("itemSaved", item);
                _this.triggerEvent("changed", item);
                return item;
              });
            };
          })(this));
        };

        Storage.prototype.remove = function(item) {
          var url;
          this.cache.removeAll();
          if (_.isPlainObject(item)) {
            url = "" + this.url + "/" + item[this.info.idProperty];
          } else if (_.isFunction(item.id)) {
            url = "" + this.url + "/" + (item.id());
          } else {
            url = "" + this.url + "/" + item;
          }
          return $http["delete"](url).then((function(_this) {
            return function(result) {
              if (result) {
                _this.triggerEvent("itemRemoved", item);
              }
              _this.triggerEvent("changed", item);
              return new Entity(_this.name, result.data);
            };
          })(this));
        };

        Storage.prototype.get = function(item) {
          if (_.isPlainObject(item)) {
            item = item[this.info.idProperty];
          }
          return $http.get("" + this.url + "/" + item, {
            cache: this.cache
          }).then((function(_this) {
            return function(result) {
              return new Entity(_this.name, result.data);
            };
          })(this));
        };

        Storage.prototype.sorted = function(order, callback, errorCallback) {
          return this.storage.query({
            _orderby: order
          }, (function(_this) {
            return function(result) {
              return callback(new Collection(_this.name, result, 0, 0, _this.entityClass));
            };
          })(this), errorCallback);
        };

        Storage.prototype.query = function(q) {
          var item, key;
          if (q != null ? q.reset : void 0) {
            this.cache.removeAll();
            delete q.reset;
          }
          for (key in q) {
            item = q[key];
            if (_.isPlainObject(item)) {
              q[key] = JSON.stringify(item);
            }
          }
          return $http.get(this.url, {
            params: q,
            cache: this.cache
          }).then((function(_this) {
            return function(result) {
              var data;
              data = result.data;
              return new Collection(_this.name, data, q, _this.entityClass);
            };
          })(this));
        };

        Storage.prototype.clearCache = function() {
          return this.cache.removeAll();
        };

        Storage.prototype.triggerEvent = function(event, item) {
          var callback, deferred, promises, resolveCallback, result, _i, _len, _ref;
          promises = [];
          if (this.eventCallbacks[event]) {
            _ref = this.eventCallbacks[event];
            for (_i = 0, _len = _ref.length; _i < _len; _i++) {
              callback = _ref[_i];
              result = callback(item);
              if (result != null ? result.then : void 0) {
                promises.push(result);
              }
            }
          }
          deferred = $q.defer();
          resolveCallback = function(result) {
            if (promises.length === 0) {
              return deferred.resolve(result);
            } else {
              return promises.shift().then(resolveCallback);
            }
          };
          if (promises.length === 0) {
            return $q.when(item);
          }
          promises.shift().then(resolveCallback);
          return deferred.promise;
        };

        Storage.prototype.itemRemoved = function(fn) {
          return this.on("itemRemoved", fn);
        };

        Storage.prototype.itemSaved = function(fn) {
          return this.on("itemSaved", fn);
        };

        Storage.prototype.preSave = function(fn) {
          return this.on("preSave", fn);
        };

        Storage.prototype.changed = function(fn) {
          return this.on("changed", fn);
        };

        Storage.prototype.on = function(event, fn) {
          if (!this.eventCallbacks[event]) {
            this.eventCallbacks[event] = [];
          }
          return this.eventCallbacks[event].push(fn);
        };

        return Storage;

      })();
    }
  ]);

}).call(this);
