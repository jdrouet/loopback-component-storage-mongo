expect          = require('chai').expect
fs              = require 'fs'
Grid            = require 'gridfs-stream'
GridStore       = require('mongodb').GridStore
ObjectID        = require('mongodb').ObjectID
loopback        = require 'loopback'
mongo           = require 'mongodb'
path            = require 'path'
StorageService  = require '../source'
request         = require 'supertest'

insertTestFile = (ds, container, done) ->
  options =
    filename: 'item.png'
    mode: 'w'
    metadata:
      'mongo-storage': true
      container: container
      filename: 'item.png'
  gfs = Grid(ds.connector.db, mongo)
  write = gfs.createWriteStream options
  read = fs.createReadStream path.join __dirname, 'files', 'item.png'
  read.pipe write
  write.on 'close', -> done()

describe 'mongo gridfs connector', ->

  agent       = null
  app         = null
  datasource  = null
  server      = null

  describe 'datasource', ->

    it 'should exist', ->
      expect(StorageService).to.exist

    describe 'default configuration', ->

      before (done) ->
        datasource = loopback.createDataSource
          connector: StorageService
          hostname: '127.0.0.1'
          port: 27017
        setTimeout done, 200
      
      it 'should create the datasource', ->
        expect(datasource).to.exist
        expect(datasource.connector).to.exist
        expect(datasource.settings).to.exist

      it 'should create the url', ->
        expect(datasource.settings.url).to.exist
        expect(datasource.settings.url).to.eql "mongodb://127.0.0.1:27017/test"

      it 'should be connected', ->
        expect(datasource.connected).to.eql true

  describe 'model usage', ->

    model = null

    before (done) ->
      datasource = loopback.createDataSource
        connector: StorageService
        hostname: '127.0.0.1'
        port: 27017
      model = datasource.createModel 'MyModel'
      setTimeout done, 200

    it 'should create the model', ->
      expect(model).to.exist

    describe 'getContainers function', ->

      it 'should exist', ->
        expect(model.getContainers).to.exist

      it 'should return an empty list', (done) ->
        model.getContainers (err, list) ->
          expect(Array.isArray list).to.eql true
          done()

    describe 'getContainer function', ->

      it 'should exist', ->
        expect(model.getContainer).to.exist

    describe 'upload function', ->

      it 'should exist', ->
        expect(model.upload).to.exist

  describe 'application usage', ->

    app     = null
    ds      = null
    server  = null
    
    before (done) ->
      app = loopback()
      app.set 'port', 5000
      app.set 'url', '127.0.0.1'
      app.set 'legacyExplorer', false
      app.use loopback.rest()
      ds = loopback.createDataSource
        connector: StorageService
        hostname: '127.0.0.1'
        port: 27017
      model = ds.createModel 'MyModel', {},
        base: 'Model'
        plural: 'my-model'
      app.model model
      setTimeout done, 200

    before (done) ->
      ds.connector.db.collection('fs.files').remove {}, done

    before (done) ->
      server = app.listen done

    after ->
      server.close()

    describe 'getContainers', ->

      describe 'without data', ->

        it 'should return an array', (done) ->
          request 'http://127.0.0.1:5000'
          .get '/my-model'
          .end (err, res) ->
            expect(res.status).to.equal 200
            expect(Array.isArray res.body).to.equal true
            expect(res.body.length).to.equal 0
            done()

      describe 'with data', ->

        before (done) ->
          insertTestFile ds, 'my-cats', done

        it 'should return an array', (done) ->
          request 'http://127.0.0.1:5000'
          .get '/my-model'
          .end (err, res) ->
            expect(res.status).to.equal 200
            expect(Array.isArray res.body).to.equal true
            expect(res.body.length).to.equal 1
            expect(res.body[0].container).to.equal 'my-cats'
            done()

    describe 'getContainer', ->

      describe 'without data', ->

        it 'should return an array', (done) ->
          request 'http://127.0.0.1:5000'
          .get '/my-model/fake-container'
          .end (err, res) ->
            expect(res.status).to.equal 200
            expect(res.body.container).to.equal 'fake-container'
            expect(Array.isArray res.body.files).to.equal true
            expect(res.body.files.length).to.equal 0
            done()

      describe 'with data', ->

        before (done) ->
          insertTestFile ds, 'my-cats-1', done

        it 'should return an array', (done) ->
          request 'http://127.0.0.1:5000'
          .get '/my-model/my-cats-1'
          .end (err, res) ->
            expect(res.status).to.equal 200
            expect(res.body.container).to.equal 'my-cats-1'
            expect(Array.isArray res.body.files).to.equal true
            expect(res.body.files.length).to.equal 1
            done()

    describe 'upload', ->

      it 'should return 20x', (done) ->
        request 'http://127.0.0.1:5000'
        .post '/my-model/my-cats/upload'
        .attach 'file', path.join(__dirname, 'files', 'item.png')
        .end (err, res) ->
          expect(res.status).to.equal 200
          done()

    describe 'download', ->
   
      before (done) ->
        ds.connector.db.collection('fs.files').remove {}, done
     
      before (done) ->
        insertTestFile ds, 'my-cats', done

      it 'should return the file', (done) ->
        request 'http://127.0.0.1:5000'
        .get '/my-model/my-cats/download/item.png'
        .end (err, res) ->
          expect(res.status).to.equal 200
          done()

    describe 'removeFile', ->
 
      before (done) ->
        ds.connector.db.collection('fs.files').remove {}, done
     
      before (done) ->
        insertTestFile ds, 'my-cats', done

      it 'should return the file', (done) ->
        request 'http://127.0.0.1:5000'
        .delete '/my-model/my-cats/files/item.png'
        .end (err, res) ->
          expect(res.status).to.equal 200
          done()

    describe 'destroyContainer', ->
 
      before (done) ->
        ds.connector.db.collection('fs.files').remove {}, done
     
      before (done) ->
        insertTestFile ds, 'my-cats', done

      it 'should return the file', (done) ->
        request 'http://127.0.0.1:5000'
        .delete '/my-model/my-cats'
        .end (err, res) ->
          expect(res.status).to.equal 200
          done()
