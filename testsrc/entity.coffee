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
              validator:
                errorMessage: 'The name must be alphanumeric'
                check: (val) -> /^[A-Za-z0-9_]*$/.test(val)
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
                return entity.get('age') > 2
            # Validators can be injected.
            promisedName:
              type: String
              label: "Promised name"
              required: false
              validator: 'promisedValidator'
      ]
      fakeModule.factory('promisedValidator', ["$q", ($q) ->
        promisedValidator =
          errorMessage: "Promised name is not valid"
          check: (val) ->
            $q.when(/^[A-Za-z0-9_]*$/.test(val))
        return promisedValidator
      ])
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
      beforeEach inject (kzEntity) ->
        Entity = kzEntity

      it 'should be possible to validate entities', (done) ->
        kitty =
          name: "testar"
          alive: true
          age: 1
          id: 1
        entity = new Entity('Kitten', kitty)
        entity.validate().then (results) ->
          expect(results.valid).toBe(true)
          entity.set('name', 'testar]').validate().then (results) ->
            expect(results.valid).toBe(false)
            return results
          .then (results) ->
            entity.set('name', '').validate().then (results) ->
              expect(results.valid).toBe(false)
            .then (results) ->
              entity.set('promisedName', 'test]').validate (results) ->
                expect(results.valid).toBe(false)
                console.log(promisedName)
                done()
        @rootScope.$apply()
