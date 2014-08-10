describe 'Konzilo entities', ->
  beforeEach(module('konzilo.entity'))

  # It should be possible to define entities so that other
  # modules in the application can find information about them.
  describe 'Entity info', ->
    @entityInfo = null
    beforeEach ->
      fakeModule = angular.module('konzilo.test', ['konzilo.entity'])
      fakeModule.config ['kzEntityInfoProvider', (provider) ->
        provider.addProvider 'Kitten',
          # Each entity can have an entity storage assigned to it.
          # kzEntityStorage is used by default.
          storageController: 'kzHttpStorage',
          validator: 'kzEntityValidator',
          # Specific to kzEntityStorage, this controller uses a base URL.
          url: '/kittens'
          # The entity class to use, defaults to kzEntity, this will be injected
          # using the normal angular approach.
          entityClass: 'kzEntity'
          # Machine name for the entity. Used if no other name is specified.
          name: "kitten"
          # The label property specifies a human readable label for the
          # entity.
          labelProperty: "name"
          # The identifier that identifies the entity. This should if possible
          # be a uuid from the backend.
          idProperty: "id"
          # Properties are an optional way of definiing specific properties
          # on entities. It can be used to validate or process values before
          # they are exposed to the browser.
          properties:
            id:
              label: "Identifier"
              # The type is optional but can be used for generic code to make
              # useful assumptions about your code.
              type: Number
            name:
              label: "Kitten name"
              required: true
              type: String
              validators: [
                {
                  errorMessage: 'The name must be alphanumeric'
                  check: (val) -> /^[A-Za-z0-9_]*$/.test(val)
                }
              ]
            alive:
              type: Boolean
              label: "Alive"
            age:
              type: Number
              label: "Age"
            cute:
              type: String
              label: "Cute"
              mutable: false
              # A processor processes data when an entity is fetched.
              processor: (val, entity) ->
                # Kittens that are older than 2 years old are not cute.
                return entity.get('age') < 2
            old:
              type: String
              label: "Old"
              mutable: false
              # A processor can be injected.
              processor: 'injectedProcessor'

            # Validators can be injected.
            promisedName:
              type: String
              label: "Promised name"
              required: false
              validators: ['promisedValidator']
      ]
      fakeModule.factory('promisedValidator', ["$q", ($q) ->
        promisedValidator =
          errorMessage: "Promised name is not valid"
          check: (val) ->
            $q.when(/^[A-Za-z0-9_]*$/.test(val))
        return promisedValidator
      ])
      fakeModule.service 'injectedProcessor', ->
        (val, entity) -> entity.get('age') > 10

      module('konzilo.test', 'konzilo.entity')
      inject ->

    beforeEach inject (kzEntityInfo, kzEntityManager,
      $rootScope, $httpBackend, $q) ->
      @entityInfo = kzEntityInfo
      @manager = kzEntityManager
      @rootScope = $rootScope
      @httpBackend = $httpBackend
      @q = $q

    describe "Entity CRUD", ->
      it 'should have a defined Kitten entity type', ->
        expect(@entityInfo('Kitten')).toBeDefined()

      it 'should not have a defined Dog entity type', ->
        expect(@entityInfo('Dog')).not.toBeDefined()

      it 'should be possible to create and update kittens', (done) ->
        kitty =
          label: 'ms kitty'
          name: 'ms_kitty'
          alive: true
          age: 1

        updatedKitty = _.defaults
          id: 1
          alive: false
        , kitty
        @httpBackend.whenPOST('/kittens', kitty)
          .respond(_.merge({ id: 1 }, kitty))

        @manager('Kitten').save(kitty).then (kitty) =>
          expect(kitty).toBeDefined()
          expect(kitty.id()).toBe(1)
          expect(kitty.get('label')).toBe('ms kitty')
          expect(kitty.get('cute')).toBe(true)
          expect(kitty.get('old')).toBe(false)
          kitty.set('alive', false)
          @httpBackend.whenPUT('/kittens/1').respond(updatedKitty)
          kitty.save().then (updatedKitty) ->
            expect(updatedKitty.get('alive')).toBe(false)
            done()
        @rootScope.$apply()
        @httpBackend.flush()

      it 'should be possible to fetch a list of entities as a collection',
      (done) ->
        cats = for cat in ['ms kitty', 'mr kitty', 'garfield']
          label: cat
          name: cat
          alive: true
          age: 1
        @httpBackend.expectGET('/kittens').respond(cats)
        @manager('Kitten').query().then (result) ->
          expect(result).toBeDefined()
          expect(result.count).toBe(3)
          expect(result.toArray().length).toBe(3)
          entity = result.find(label: 'mr kitty')
          expect(entity).toBeDefined()
          expect(result.hasItem(entity)).toBe(true)
          done()

        @rootScope.$apply()
        @httpBackend.flush()

      it 'should be possible to fetch the raw data without a wrapper', (done) ->
        cats = for cat in ['ms kitty', 'mr kitty', 'garfield']
            label: cat
            name: cat
            alive: true
            age: 1
        @httpBackend.expectGET('/kittens').respond(cats)
        @manager('Kitten').query({}, wrapped: false).then (result) ->
          expect(result.length).toBe(3)
          expect(result[0].label).toBe('ms kitty')
          done()

        @rootScope.$apply()
        @httpBackend.flush()

      it 'should be possible to fetch individual entities', (done) ->
        kitty =
          label: 'ms kitty'
          name: 'ms_kitty'
          alive: true
          age: 1
          id: 1
        @httpBackend.whenGET('/kittens/1').respond(kitty)
        @manager('Kitten').get(1).then (result) ->
          expect(result).toBeDefined()
          expect(result.id()).toBe(1)
          done()
        @rootScope.$apply()
        @httpBackend.flush()

      it 'should be possible to delete entities', (done) ->
        kitty =
          label: 'ms kitty'
          name: 'ms_kitty'
          alive: true
          age: 1
          id: 1
        @httpBackend.whenDELETE('/kittens/1').respond(204, kitty)
        @manager('Kitten').remove(1).then (result) ->
          expect(result).toBeDefined()
          expect(result.id()).toBe(1)
          done()
        @rootScope.$apply()
        @httpBackend.flush()

    describe 'Entity events', ->
      kitty =
        label: 'ms kitty'
        name: 'ms_kitty'
        alive: false
        age: 1
      beforeEach ->
        @kittenController = @manager('Kitten')
        @httpBackend.expectPOST('/kittens', kitty).respond(kitty)
        @httpBackend.whenDELETE('/kittens/1').respond(204, kitty)

      it 'should be possible to react to entities before they are saved',
      (done) ->
        spies =
          kittyPresave: (kitty) ->
            kitty.set('alive', false)

          promisedPresave: (kitty) =>
            @q.when(kitty)

        spyOn(spies, 'kittyPresave').and.callThrough()
        spyOn(spies, 'promisedPresave').and.callThrough()

        @kittenController.preSave(spies.kittyPresave)
        @kittenController.preSave(spies.promisedPresave)

        @kittenController.save(_.defaults(alive: true, kitty)).then (result) ->
          expect(result.get('alive')).toBe(false)
          expect(spies.kittyPresave).toHaveBeenCalled()
          expect(spies.promisedPresave).toHaveBeenCalled()
          done()
        @rootScope.$apply()
        @httpBackend.flush()

      it 'should be possible to react after an entity has been saved',
      (done) ->
        spies =
          itemSaved: (kitty) ->
            kitty.set('itemSaved', true)

        spyOn(spies, 'itemSaved').and.callThrough()
        @kittenController.itemSaved(spies.itemSaved)
        @kittenController.save(kitty).then (result) ->
          expect(spies.itemSaved).toHaveBeenCalled()
          expect(result.get('itemSaved')).toBe(true)
          done()
        @rootScope.$apply()
        @httpBackend.flush()

      it 'should be possible to react after an entity has been saved',
      (done) ->
        spies =
          itemSaved: (kitty) ->
            kitty.set('itemSaved', true)
          itemChanged: (kitty) ->
            return kitty

        spyOn(spies, 'itemSaved').and.callThrough()
        spyOn(spies, 'itemChanged')
        @kittenController.itemSaved(spies.itemSaved)
        @kittenController.changed(spies.itemChanged)

        @kittenController.save(kitty).then (result) ->
          expect(spies.itemSaved).toHaveBeenCalled()
          expect(spies.itemChanged).toHaveBeenCalled()
          expect(result.get('itemSaved')).toBe(true)
          done()
        @rootScope.$apply()
        @httpBackend.flush()

        it 'should be possible to react after an entity has been removed',
        (done) ->
          spies =
            itemRemoved: (kitty) ->
              return
            itemChanged: (kitty) ->
              return

          spyOn(spies, 'itemRemoved')
          spyOn(spies, 'itemChanged')
          @kittenController.itemSaved(spies.itemRemoved)
          @kittenController.changed(spies.itemChanged)
          @kittenController.remove(1).then (result) ->
            expect(spies.itemSaved).toHaveBeenCalled()
            expect(spies.itemChanged).toHaveBeenCalled()
            done()
          @rootScope.$apply()
          @httpBackend.flush()
    describe "Entity validation", ->
      Entity = null
      entity = null
      beforeEach inject (kzEntity) ->
        Entity = kzEntity
        kitty =
          name: "testar"
          alive: true
          age: 1
          id: 1
        entity = new Entity('Kitten', kitty)
      it 'should be possible to use custom validators', (done) ->
        entity.set('name', 'testar]')
        entity.validate().then (results) ->
          expect(results.valid).toBe(false)
          expect(results.properties.name.valid).toBe(false)
          expect(results.properties.name.results[0].message)
            .toBe('The name must be alphanumeric')
          done()
        @rootScope.$apply()
      it 'should be possible to use injected validators that uses promises',
      (done) ->
        entity.set('promisedName', 'test]').validate().then (results) ->
          expect(results.valid).toBe(false)
          expect(results.properties.promisedName.valid).toBe(false)
          expect(results.properties.promisedName.results[0].message)
            .toBe('Promised name is not valid')
          done()
        @rootScope.$apply()
      it 'should be possible to invalidate entities when required values are missing',
        (done) ->
          entity.set('name', '').validate().then (results) ->
            expect(results.valid).toBe(false)
            expect(results.properties.name.valid).toBe(false)
            done()
          @rootScope.$apply()
